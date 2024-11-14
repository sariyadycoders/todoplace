defmodule TodoplaceWeb.GalleryLive.Photos.Upload do
  @moduledoc false
  use TodoplaceWeb, :live_view

  alias Todoplace.{Galleries, Photos}

  alias Galleries.{
    Photo,
    PhotoProcessing.GalleryUploadProgress
  }

  alias Phoenix.PubSub

  import TodoplaceWeb.GalleryLive.Shared,
    only: [disabled?: 1, start_photo_processing: 2, get_gallery!: 1]

  @upload_options [
    accept: ~w(.jpg .jpeg .png image/jpeg image/png),
    max_entries: String.to_integer(Application.compile_env(:todoplace, :photos_max_entries)),
    max_file_size: String.to_integer(Application.compile_env(:todoplace, :photo_max_file_size))
  ]
  @bucket Application.compile_env(:todoplace, :photo_storage_bucket)

  # guide for later
  # move all pubsub related methods to new file within same directory
  # move all helper methods that doesn't return socket in separate file
  # keep in_progress_photos in map instead of list
  defmodule Entry do
    @moduledoc false
    @derive Jason.Encoder
    defstruct uuid: nil,
              error: nil,
              client_name: nil,
              client_size: nil,
              client_type: nil,
              progress: 0

    def build(files) do
      Enum.map(files, fn file ->
        %__MODULE__{
          client_name: file["name"],
          client_size: file["size"],
          uuid: file["id"],
          client_type: file["type"],
          error: file["error"]
        }
      end)
    end
  end

  @impl true
  def mount(_params, %{"gallery_id" => gallery_id} = session, socket) do
    view = Map.get(session, "view", "add_button")

    gallery = get_gallery!(gallery_id)

    if connected?(socket) && view == "add_button" do
      PubSub.subscribe(Todoplace.PubSub, "upload_update:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "upload_pending_photos:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "inprogress_upload_update:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "delete_photos:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "folder_albums:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "upload_stuck_photos:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "on_new_album:#{gallery_id}")
    end

    {:ok,
     socket
     |> assign(:upload_bucket, @bucket)
     |> assign(:view, view)
     |> assign(:album_id, Map.get(session, "album_id", nil))
     |> assign(:gallery, gallery)
     |> assigns()
     |> assign(:overall_progress, 0)
     |> assign(:uploaded_files, 0)
     |> assign(:progress, %GalleryUploadProgress{})
     |> assign(:estimate, "n/a")
     |> assign(:folder_albums, %{})
     |> assign(:update_mode, "append"), layout: false}
  end

  def handle_event(
        "get_signed_url",
        %{"files" => files, "gallery_id" => gallery_id},
        socket
      ) do
    uploading_broadcast(socket, gallery_id, true)

    files
    |> Entry.build()
    |> apply_limits(socket)
    |> update_progress()
    |> then(fn %{
                 assigns: %{
                   inprogress_photos: entries,
                   invalid_photos: invalid_photos,
                   pending_photos: pending_photos
                 }
               } = socket ->
      invalid = Map.new(invalid_photos ++ pending_photos, &{&1.uuid, &1})
      send(self(), {:build_urls, entries, gallery_id, invalid})

      socket
      |> noreply()
    end)
  end

  def handle_event(
        "add_resumeable_photos",
        %{
          "name" => _,
          "gallery_id" => gallery_id
        } = file,
        %{assigns: %{inprogress_photos: inprogress_photos}} = socket
      ) do
    [entry] = Entry.build([file])
    broadcast_new_entry(gallery_id, entry.uuid, entry.client_name)

    socket
    |> assign(:inprogress_photos, [entry | inprogress_photos])
    |> update_progress()
    |> noreply()
  end

  def handle_event("add_albums", %{"albums" => albums}, socket) do
    albums =
      albums
      |> Enum.reduce(%{}, fn {name, %{"id" => id}}, acc ->
        Map.put(acc, name, %{id: id})
      end)

    socket
    |> assign(
      :folder_albums,
      albums
    )
    |> noreply()
  end

  def handle_event("pending_photos", %{"files" => files}, socket) do
    {pending_photos, invalid_photos} =
      files
      |> Entry.build()
      |> Enum.split_with(&is_nil(&1.error))

    socket
    |> assign(:pending_photos, pending_photos)
    |> assign(:invalid_photos, invalid_photos)
    |> assign(:photos_error_count, length(pending_photos ++ invalid_photos))
    |> photos_error_broadcast()
    |> noreply()
  end

  @impl true
  def handle_event(
        "photo_done",
        %{"id" => id, "name" => name, "album_id" => album_id_stored},
        %{
          assigns: %{
            gallery: gallery,
            album_id: album_id,
            folder_albums: folder_albums
          }
        } = socket
      ) do
    album_id =
      album_id || if is_nil(album_id_stored), do: nil, else: String.to_integer(album_id_stored)

    entry = %{uuid: id, client_name: name}

    {:ok, photo} = create_photo(gallery, entry, album_id, folder_albums)
    {:ok, _gallery} = Galleries.update_gallery(gallery, %{total_count: gallery.total_count + 1})

    photo
    |> Todoplace.Repo.preload(:album)
    |> start_photo_processing(gallery)

    PubSub.broadcast(
      Todoplace.PubSub,
      "photos_stream:#{gallery.id}",
      {:photo_insert, photo}
    )

    socket
    |> noreply
  end

  # this handle event causes process to consume high memory
  def handle_event(
        "progress_custom",
        %{
          "id" => id,
          "progress" => progress
        } = file,
        %{
          assigns: %{
            uploaded_files: uploaded_files,
            progress: progress_struct,
            inprogress_photos: inprogress_photos
          }
        } = socket
      ) do
    # later note: make inprogress_photos map and then get entry from it
    entry =
      inprogress_photos
      |> Enum.find(%{}, &(&1.uuid == id))
      |> Map.put(:progress, progress)

    {progress, entry}
    |> case do
      {100, %Entry{}} ->
        socket
        |> assign(:uploaded_files, uploaded_files + 1)
        |> assign(:progress, GalleryUploadProgress.complete_upload(progress_struct, entry))
        |> assign(:inprogress_photos, Enum.reject(inprogress_photos, &(&1.uuid == id)))
        |> assign_overall_progress()

      {_, %Entry{}} ->
        assign_overall_progress(socket, entry)

      {_, %{progress: progress}} ->
        entry =
          [file]
          |> Entry.build()
          |> Enum.at(0)
          |> Map.put(:progress, progress)

        socket
        |> assign(:inprogress_photos, [entry | inprogress_photos])
        |> update_progress()

      _ ->
        socket
    end
    |> noreply()
  end

  def handle_event(
        "processing_message",
        %{"show" => show?},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    PubSub.broadcast(
      Todoplace.PubSub,
      "processing_message:#{gallery.id}",
      {:processing_message, show?}
    )

    socket |> noreply()
  end

  def handle_event("close", _, socket) do
    send(self(), :close_upload_popup)

    socket |> noreply()
  end

  def handle_event("remove-uploading", %{"ids" => ids}, %{assigns: %{gallery: gallery}} = socket) do
    PubSub.broadcast(Todoplace.PubSub, "photos_stream:#{gallery.id}", {:remove_uploading, ids})

    socket
    |> assign(:inprogress_photos, [])
    |> noreply()
  end

  defp broadcast_new_entry(gallery_id, entry_id, name) do
    PubSub.broadcast(
      Todoplace.PubSub,
      "photos_stream:#{gallery_id}",
      {:photos_stream,
       %{
         id: entry_id,
         name: name
       }}
    )
  end

  @impl true
  def handle_info(
        {:upload_update, %{album_id: album_id}},
        socket
      ) do
    photos_error_broadcast(socket)

    socket
    |> assign(:album_id, album_id)
    |> noreply()
  end

  @impl true
  def handle_info(
        {:build_urls, [], _gallery_id, _invalid},
        socket
      ) do
    socket
    |> push_event("save_and_display", %{urls: %{}, invalid: %{}, is_remove_message: true})
    |> noreply()
  end

  @impl true
  def handle_info(
        {:build_urls, entries, gallery_id, invalid},
        socket
      ) do
    {entries, pending_entries} = Enum.split(entries, 300)
    Enum.each(entries, &broadcast_new_entry(gallery_id, &1.uuid, &1.client_name))

    urls =
      entries
      |> Task.async_stream(
        fn entry ->
          key = Photo.original_path(entry.client_name, gallery_id, entry.uuid)
          {:ok, url} = Photos.initialize_resumable(key, entry.client_name)

          {entry.uuid, url}
        end,
        timeout: :infinity,
        max_concurrency: 100
      )
      |> Enum.reduce(%{}, fn {:ok, {uuid, url}}, acc -> Map.put(acc, uuid, url) end)

    send(self(), {:build_urls, pending_entries, gallery_id, invalid})

    socket
    |> push_event("save_and_display", %{urls: urls, invalid: invalid, is_remove_message: false})
    |> noreply()
  end

  def handle_info(
        {:delete_photos, %{index: index, delete_from: delete_from}},
        %{assigns: %{photos_error_count: photos_error_count} = assigns} = socket
      ) do
    index
    |> case do
      [] ->
        socket |> assigns() |> push_event("delete_pending_photos", %{delete_all: true})

      index ->
        {entry, pending_entries} = assigns[delete_from] |> List.pop_at(index)

        socket
        |> assign(delete_from, pending_entries)
        |> assign(:photos_error_count, photos_error_count - if(is_nil(entry), do: 0, else: 1))
        |> push_event("delete_pending_photos", %{delete_all: false, photo: entry})
    end
    |> photos_error_broadcast()
    |> noreply()
  end

  def handle_info(
        {:upload_pending_photos, %{index: index}},
        %{
          assigns: %{
            gallery: gallery,
            pending_photos: pending_photos,
            photos_error_count: photos_error_count
          }
        } = socket
      ) do
    gallery = Galleries.load_watermark_in_gallery(gallery)

    assign_items = fn socket, pending_entries, photos_error_count, valid_entries ->
      socket
      |> assign(:pending_photos, pending_entries)
      |> assign(:photos_error_count, photos_error_count - length(valid_entries))
      |> assign(:valid_entries, valid_entries)
    end

    index
    |> case do
      [] ->
        {valid_entries, pending_entries} =
          pending_photos
          |> Enum.chunk_every(Keyword.get(@upload_options, :max_entries))
          |> List.pop_at(0)

        valid_entries = valid_entries || []

        assign_items.(socket, pending_entries, photos_error_count, valid_entries)

      index ->
        {valid_entry, pending_entries} = pending_photos |> List.pop_at(index)
        valid_entries = (valid_entry && [valid_entry]) || []

        assign_items.(socket, pending_entries, photos_error_count, valid_entries)
    end
    |> update_progress()
    |> assign(:gallery, gallery)
    |> then(fn
      %{assigns: %{valid_entries: []}} = socket ->
        socket

      %{assigns: %{valid_entries: valid_entries}} = socket ->
        valid_entries = Map.new(valid_entries, &{&1.uuid, &1})

        socket
        |> push_event("resume_pending_photos", %{photos: valid_entries})
        |> assign(:valid_entries, [])
    end)
    |> noreply()
  end

  def handle_info({:folder_albums, albums}, socket) do
    albums =
      albums
      |> Enum.reduce(%{}, fn {name, %{id: id}}, acc ->
        Map.put(acc, name, %{"id" => id})
      end)

    socket
    |> assign(:folder_albums, albums)
    |> push_event("folder_albums", %{"albums" => albums})
    |> noreply()
  end

  def handle_info({:new_album, album}, socket) do
    socket
    |> assign(:album_id, album.id)
    |> noreply()
  end

  defp total(list) when is_list(list), do: list |> length
  defp total(_), do: nil

  defp assign_overall_progress(%{assigns: %{progress: progress}} = socket, entry) do
    socket
    |> assign(:progress, GalleryUploadProgress.track_progress(progress, entry))
    |> assign_overall_progress()
  end

  defp assign_overall_progress(
         %{assigns: %{progress: progress, gallery: gallery, album_id: album_id}} = socket
       ) do
    total_progress = GalleryUploadProgress.total_progress(progress)
    estimate = GalleryUploadProgress.estimate_remaining(progress, DateTime.utc_now())

    gallery_progress_broadcast(socket, total_progress)

    total_progress
    |> case do
      100 ->
        process_items(gallery, album_id)

        socket
        |> assign(:inprogress_photos, [])
        |> assign(:progress, %GalleryUploadProgress{})

      _ ->
        socket
    end
    |> assign(:overall_progress, total_progress)
    |> assign(:estimate, estimate)
  end

  defp process_items(gallery, album_id) do
    PubSub.broadcast(
      Todoplace.PubSub,
      "photo_upload_completed:#{gallery.id}",
      {:photo_upload_completed,
       %{gallery_id: gallery.id, success_message: "#{gallery.name} upload complete"}}
    )

    Galleries.update_gallery_photo_count(gallery.id)

    if album_id do
      Galleries.sort_album_photo_positions_by_name(album_id)
    else
      Galleries.sort_gallery_photo_positions_by_name(gallery.id)
    end

    Galleries.refresh_bundle(gallery)
  end

  defp photos_error_broadcast(
         %{
           assigns: %{
             gallery: gallery,
             photos_error_count: photos_error_count,
             invalid_photos: invalid_photos,
             pending_photos: pending_photos
           }
         } = socket,
         entries \\ []
       ) do
    photos_error_count > 0 &&
      PubSub.broadcast(
        Todoplace.PubSub,
        "photos_error:#{gallery.id}",
        {:photos_error,
         %{
           photos_error_count: photos_error_count,
           invalid_photos: invalid_photos,
           pending_photos: pending_photos,
           entries: entries
         }}
      )

    socket
  end

  defp gallery_progress_broadcast(
         %{
           assigns: %{
             overall_progress: overall_progress,
             gallery: gallery
           }
         } = socket,
         total_progress
       ) do
    if total_progress != overall_progress do
      PubSub.broadcast(
        Todoplace.PubSub,
        "galleries_progress:#{gallery.id}",
        {:galleries_progress, %{total_progress: total_progress, gallery_id: gallery.id}}
      )

      PubSub.broadcast(
        Todoplace.PubSub,
        "gallery_progress:#{gallery.id}",
        {:gallery_progress, %{total_progress: total_progress}}
      )
    end

    socket
  end

  defp uploading_broadcast(socket, gallery_id, uploading) do
    PubSub.broadcast(
      Todoplace.PubSub,
      "uploading:#{gallery_id}",
      {:uploading,
       %{
         pid: self(),
         uploading: uploading,
         success_message: upload_success_message(socket)
       }}
    )
  end

  # move this method to context
  defp create_photo(gallery, entry, album_id, folder_albums) do
    {album_id, name} = fetch_photo_params(entry, album_id, folder_albums)

    Galleries.create_photo(%{
      gallery_id: gallery.id,
      album_id: album_id,
      name: name,
      uuid: entry.uuid,
      original_url: Photo.original_path(name, gallery.id, entry.uuid),
      position: (gallery.total_count || 0) + 100
    })
  end

  @separator "-fsp-"
  defp fetch_photo_params(%{client_name: name}, album_id, folder_albums) do
    case String.split(name, @separator) do
      [folder_name | name] when is_map_key(folder_albums, folder_name) ->
        {folder_albums |> Map.fetch!(folder_name) |> Map.fetch!(:id), Enum.join(name)}

      _ ->
        {album_id, name}
    end
  end

  defp upload_success_message(%{
         assigns: %{entries: entries, inprogress_photos: inprogress_photos}
       }) do
    uploaded = length(inprogress_photos)
    "#{uploaded}/#{total(entries)} #{ngettext("photo", "photos", uploaded)} uploaded successfully"
  end

  defp apply_limits(
         entries,
         %{
           assigns: %{
             gallery: gallery,
             pending_photos: pending_photos
           }
         } = socket
       ) do
    {valid, invalid} = max_size_limit(entries, gallery.id)
    {valid_entries, pending_entries} = max_entries_limit(valid, pending_photos)
    pending_entries = List.flatten(pending_entries)

    socket
    |> assign(:invalid_photos, invalid)
    |> assign(:pending_photos, pending_entries)
    |> assign(:photos_error_count, length(pending_entries ++ invalid))
    |> assign(:inprogress_photos, valid_entries || [])
  end

  defp max_entries_limit(entries, pending_photos) do
    case entries do
      [entry] ->
        {[entry], Enum.reject(pending_photos, &(&1.uuid == entry.uuid))}

      _ ->
        entries
        |> Enum.chunk_every(Keyword.get(@upload_options, :max_entries))
        |> List.pop_at(0)
    end
  end

  defp max_size_limit(entries, gallery_id) do
    Enum.reduce(entries, {[], []}, fn entry, {valid, invalid} = acc ->
      if entry.client_size < Keyword.get(@upload_options, :max_file_size) do
        filter_wrong_extensions(entry, acc, gallery_id)
      else
        {valid, [Map.put(entry, :error, "File too large") | invalid]}
      end
    end)
  end

  defp filter_wrong_extensions(entry, {valid, invalid} = acc, gallery_id) do
    if entry.client_type in Keyword.get(@upload_options, :accept, []) do
      duplicate_entries(entry, acc, gallery_id)
    else
      {valid, [Map.put(entry, :error, "Invalid file type") | invalid]}
    end
  end

  defp duplicate_entries(entry, {valid, invalid}, nil), do: {[entry | valid], invalid}

  # improve this code
  # check incoming files first for duplication then fetch all gallery photos for once and make it map to find existing
  # photos
  defp duplicate_entries(%{client_name: client_name} = entry, {valid, invalid}, gallery_id) do
    client_name
    |> Galleries.duplicate?(gallery_id)
    |> case do
      true ->
        {valid, [Map.put(entry, :error, "Duplicate") | invalid]}

      _ ->
        {[entry | valid], invalid}
    end
  end

  defp update_progress(%{assigns: %{inprogress_photos: inprogress_photos}} = socket) do
    photos_error_broadcast(socket)

    socket
    |> assign(
      :progress,
      Enum.reduce(
        inprogress_photos,
        socket.assigns.progress,
        fn entry, progress -> GalleryUploadProgress.add_entry(progress, entry) end
      )
    )
  end

  defp assigns(socket) do
    socket
    |> assign(:invalid_photos, [])
    |> assign(:pending_photos, [])
    |> assign(:inprogress_photos, [])
    |> assign(:entries, [])
    |> assign(:photos_error_count, 0)
  end

  defp add_photo_button(assigns) do
    ~H"""
    <%= if @disable do %>
      <div class={@class}><%= render_slot(@inner_block) %></div>
    <% else %>
      <button disabled="disabled" class={"#{@class} disabled:opacity-50 disabled:cursor-not-allowed"}>
        <%= render_slot(@inner_block) %>
      </button>
    <% end %>
    """
  end
end
