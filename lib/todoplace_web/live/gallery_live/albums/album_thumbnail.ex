defmodule TodoplaceWeb.GalleryLive.Albums.AlbumThumbnail do
  @moduledoc false
  use TodoplaceWeb, :live_component

  require Logger
  import TodoplaceWeb.LiveHelpers
  import TodoplaceWeb.GalleryLive.Shared

  alias Todoplace.{Repo, Galleries, Albums}

  @per_page 999_999

  def preload([assigns | _]) do
    %{gallery_id: gallery_id, album_id: album_id} = assigns

    gallery = Galleries.get_gallery!(gallery_id) |> Repo.preload(:albums)
    album = album_id |> Albums.get_album!() |> Repo.preload([:photos, :thumbnail_photo])

    thumbnail =
      case album.thumbnail_photo_id do
        nil -> nil
        photo_id -> Todoplace.Photos.get(photo_id)
      end

    [
      Map.merge(assigns, %{
        gallery: gallery,
        album: album,
        page_title: "Album thumbnail",
        thumbnail: thumbnail,
        favorites_count: Galleries.gallery_favorites_count(gallery),
        title: album.name,
        frame_id: 2
      })
    ]
  end

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(
      description:
        "Select one of the photos in your album to use as your album thumbnail. Your client will see this on their main gallery page.",
      favorites_filter: false,
      page: 0,
      selected: false
    )
    |> assign_photos(@per_page)
    |> ok()
  end

  def handle_event(
        "click",
        %{"preview_photo_id" => preview_photo_id},
        socket
      ) do
    preview_photo_id = to_integer(preview_photo_id)

    socket
    |> assign(
      selected: true,
      preview_photo_id: preview_photo_id,
      thumbnail: Galleries.get_photo(preview_photo_id)
    )
    |> push_event("reload_grid", %{})
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        _,
        %{assigns: %{album: album, thumbnail: thumbnail}} = socket
      ) do
    album |> Albums.save_thumbnail(thumbnail)

    send(self(), {:save, %{message: "Album thumbnail successfully updated"}})

    socket
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-screen h-screen overflow-auto bg-white">
      <.preview
        description={@description}
        favorites_count={@favorites_count}
        favorites_filter={@favorites_filter}
        gallery={@gallery}
        has_more_photos={@has_more_photos}
        page={@page}
        page_title={@page_title}
        streams={@streams}
        selected={@selected}
        myself={@myself}
        title={@title}
      >
        <div class="flex items-start justify-center bg-gray-300 row-span-2 previewImg">
          <.framed_preview photo={@thumbnail || album_placeholder()} item_id={@album.id} />
        </div>
      </.preview>
    </div>
    """
  end

  def album_placeholder() do
    %Todoplace.Galleries.Photo{
      original_url: TodoplaceWeb.Endpoint.static_path("/images/album_placeholder.png"),
      height: 1330,
      width: 1630
    }
  end

  defdelegate framed_preview(assigns), to: TodoplaceWeb.GalleryLive.FramedPreviewComponent
end
