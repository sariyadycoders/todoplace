defmodule TodoplaceWeb.GalleryLive.Shared.SideNavComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  import TodoplaceWeb.GalleryLive.Shared
  import Todoplace.Utils, only: [products_currency: 0]
  import TodoplaceWeb.Shared.EditNameComponent, only: [edit_name_input: 1]
  import Todoplace.Albums, only: [get_all_albums_photo_count: 1]

  alias Phoenix.PubSub
  alias Todoplace.Galleries

  @impl true
  def update(
        %{
          id: id,
          total_progress: total_progress,
          photos_error_count: photos_error_count,
          gallery: gallery,
          arrow_show: arrow_show,
          album_dropdown_show: album_dropdown_show,
          is_mobile: is_mobile
        } = params,
        socket
      ) do
    if connected?(socket) do
      PubSub.subscribe(Todoplace.PubSub, "photos_error:#{gallery.id}")
      PubSub.subscribe(Todoplace.PubSub, "gallery_progress:#{gallery.id}")
    end

    currency = Todoplace.Currency.for_gallery(gallery)
    album = Map.get(params, :selected_album)

    Phoenix.PubSub.broadcast(
      Todoplace.PubSub,
      "upload_update:#{gallery.id}",
      {:upload_update, %{album_id: album && album.id}}
    )

    socket
    |> assign(:id, id)
    |> assign(:total_progress, total_progress)
    |> assign(:photos_error_count, photos_error_count)
    |> assign(:gallery, gallery)
    |> assign(:currency, currency)
    |> assign(:edit_name, false)
    |> assign(:is_mobile, is_mobile)
    |> assign(:arrow_show, arrow_show)
    |> assign(:album_dropdown_show, album_dropdown_show)
    |> assign(:selected_album, album)
    |> assign_gallery_changeset()
    |> assign_counts()
    |> ok()
  end

  def update(%{gallery: _, total_progress: _} = assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_counts()
    |> ok
  end

  defp assign_counts(%{assigns: %{total_progress: total_progress, gallery: gallery}} = socket) do
    idle? = total_progress_idle?(total_progress)

    socket
    |> assign(
      :albums,
      gallery.id
      |> get_all_gallery_albums()
      |> maybe_album_map_count(total_progress, gallery.id)
    )
    |> assign(:total_count, if(idle?, do: Galleries.get_gallery_photo_count(gallery.id)))
    |> assign(
      :unsorted_count,
      if(idle?, do: Galleries.get_gallery_unsorted_photo_count(gallery.id))
    )
  end

  @impl true
  def handle_event(
        "select_albums_dropdown",
        _,
        %{
          assigns: %{
            album_dropdown_show: album_dropdown_show
          }
        } = socket
      ) do
    socket
    |> assign(:album_dropdown_show, !album_dropdown_show)
    |> noreply()
  end

  defp bar(assigns) do
    ~H"""
    <div class={@class}>
      <.link navigate={@route}>
        <div class="flex items-center py-3 pl-3 pr-4 overflow-hidden text-sm rounded lg:h-11 lg:pl-2 lg:py-4 transition duration-300 ease-in-out text-ellipsis whitespace-nowrap hover:text-blue-planning-300">
          <div class="flex items-center justify-center flex-shrink-0 w-8 h-8 rounded-full bg-blue-planning-300">
              <img src={static_path(TodoplaceWeb.Endpoint, "/images/#{@icon}")} width="16" height="16"/>
          </div>
          <div class="ml-3">
            <span class={@arrow_show && "text-blue-planning-300"}><%= @title %></span>
          </div>
          <div class="flex items-center px-2 ml-auto">
            <%= render_slot(@inner_block) %>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  defp li(assigns) do
    assigns = Enum.into(assigns, %{is_proofing: false, is_finals: false, photos_count: nil})

    ~H"""
    <div class={"#{@class}"}>
      <.link navigate={@route}>
        <li class="group">
          <button class={"#{@button_class} flex items-center justify-between h-6 py-4 pl-12 w-full pr-6 overflow-hidden text-xs transition duration-300 ease-in-out rounded-lg text-ellipsis whitespace-nowrap group-hover:!text-blue-planning-300"}>
              <div class="flex items-center justify-between">
                <.icon name={@name} class={"w-4 h-4 stroke-2 fill-current #{@button_class} mr-2 group-hover:!text-blue-planning-300"}/>
                <%= if @is_finals, do: "Proofing " %>
                <%= if @is_proofing || @is_finals, do: String.capitalize(@title), else: @title %>
              </div>
              <%= if @photos_count do %>
                <.photo_count photos_count={@photos_count} />
              <% end %>
          </button>
        </li>
      </.link>
    </div>
    """
  end

  defp photo_count(assigns) do
    assigns = Enum.into(assigns, %{photos_count: 0})

    ~H"""
      <span class="bg-white px-1 py-0.5 rounded-full min-w-[30px] font-normal text-xs flex items-center justify-center ml-auto" {testid("photo-count")}><%= @photos_count %></span>
    """
  end

  defp get_select_photo_route(socket, albums, gallery, opts) do
    if Enum.empty?(albums) do
      ~p"/galleries/#{gallery}/photos?#{opts}"
    else
      ~p"/galleries/#{gallery}/albums?#{opts}"
    end
  end

  defp is_selected_album(album, selected_album),
    do: selected_album && album.id == selected_album.id

  defp icon_name(album) do
    cond do
      album.is_proofing -> "proofing"
      album.is_finals -> "finals"
      album.is_client_liked -> "heart-filled"
      true -> "standard_album"
    end
  end

  defp total_progress_idle?(total_progress), do: total_progress == 0 || total_progress == 100

  defp maybe_album_map_count(albums, total_progress, gallery_id) do
    if total_progress_idle?(total_progress) do
      albums_count = get_all_albums_photo_count(gallery_id)

      albums
      |> Enum.map(
        &Map.put(
          &1,
          :photos_count,
          albums_count
          |> Enum.find(fn %{album_id: album_id, count: _} -> album_id == &1.id end)
          |> then(fn
            map ->
              if &1.id == "client_liked", do: length(&1.photos), else: Map.get(map, :count, 0)
          end)
        )
      )
    else
      albums
    end
  end
end
