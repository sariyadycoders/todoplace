defmodule TodoplaceWeb.GalleryLive.Photos.UploadError do
  @moduledoc false
  use TodoplaceWeb, :live_component

  alias Phoenix.PubSub

  import TodoplaceWeb.JobLive.Shared, only: [files_to_upload: 1]

  @string_length 35

  @impl true
  def mount(socket) do
    socket
    |> assign(:string_length, @string_length)
    |> ok()
  end

  @impl true
  def handle_event(
        "delete_photo",
        %{"index" => index, "delete_from" => delete_from},
        %{assigns: assigns} = socket
      ) do
    delete_from = String.to_atom(delete_from)
    index = String.to_integer(index)
    {_, pending_photos} = assigns[delete_from] |> List.pop_at(index)

    delete_broadcast(assigns.gallery.id, index, delete_from)

    socket
    |> assign(delete_from, pending_photos)
    |> then(fn %{assigns: %{invalid_photos: invalid_photos, pending_photos: pending_photos}} =
                 socket ->
      if Enum.empty?(pending_photos ++ invalid_photos) do
        error_broadcast(assigns.gallery.id)

        socket |> close_modal()
      else
        socket
      end
    end)
    |> noreply()
  end

  @impl true
  def handle_event("delete_all_photos", _, %{assigns: %{gallery: gallery}} = socket) do
    delete_broadcast(gallery.id, [], "delete_all")
    error_broadcast(gallery.id)

    socket
    |> close_modal()
    |> noreply()
  end

  @impl true
  def handle_event(
        "upload_pending_photos",
        %{"index" => index},
        %{
          assigns: %{
            gallery: gallery,
            invalid_photos: invalid_photos,
            pending_photos: pending_photos
          }
        } = socket
      ) do
    index = String.to_integer(index)
    {_, pending_entries} = pending_photos |> List.pop_at(index)

    upload_broadcast(gallery.id, index)

    if Enum.empty?(pending_entries ++ invalid_photos) do
      error_broadcast(gallery.id)

      socket |> close_modal()
    else
      socket
    end
    |> assign(:pending_photos, pending_entries)
    |> noreply()
  end

  @impl true
  def handle_event("upload_all_pending_photos", _, %{assigns: %{gallery: gallery}} = socket) do
    upload_broadcast(gallery.id, [])
    error_broadcast(gallery.id)

    socket
    |> close_modal()
    |> noreply()
  end

  @impl true
  def handle_event("close", _, socket) do
    socket
    |> close_modal()
    |> noreply()
  end

  defp upload_broadcast(gallery_id, index) do
    PubSub.broadcast(
      Todoplace.PubSub,
      "upload_pending_photos:#{gallery_id}",
      {:upload_pending_photos, %{index: index}}
    )
  end

  defp error_broadcast(gallery_id),
    do: PubSub.broadcast(Todoplace.PubSub, "clear_photos_error:#{gallery_id}", :clear_photos_error)

  defp delete_broadcast(gallery_id, index, delete_from) do
    PubSub.broadcast(
      Todoplace.PubSub,
      "delete_photos:#{gallery_id}",
      {:delete_photos, %{index: index, delete_from: delete_from}}
    )
  end

  defp error_type(assigns) do
    ~H"""
    <div class="pl-4">
      <%= cond do %>
      <% @invalid_count > 0 && @pending_count == 0 -> %>
        It looks like some of your photos failed because they’re duplicate photos, invalid file type or over our photo size limit. We accept photos up to
        <span class="font-bold">100MB </span>
        in size. Please reduce the file size or change the file name of these photos and reupload.

      <% @invalid_count == 0 && @pending_count > 0 -> %>
        We can only upload
        <span class="font-bold">1,500 photos at a time</span>
        , so some of your photos are still in the upload queue. You can retry uploading these photos below.

      <% true -> %>
        It looks like some of your photos failed because they’re duplicate photos, invalid file type or over our photo size limit. We accept photos up to
        <span class="font-bold">100MB </span>in size. Please reduce the file size or change the file name of these photos and reupload.<br>
        <br>
        We can only upload
        <span class="font-bold">1,500 photos at a time</span>
        , so some of your photos are still in the upload queue. You can retry uploading these photos below.
      <% end %>
    </div>
    """
  end
end
