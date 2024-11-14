defmodule TodoplaceWeb.GalleryLive.ProductPreview.EditProduct do
  @moduledoc "no doc"
  use TodoplaceWeb, :live_component

  require Logger
  import TodoplaceWeb.LiveHelpers
  import TodoplaceWeb.GalleryLive.Shared

  alias Todoplace.{Galleries, Repo, GalleryProducts}
  alias Galleries.Photo

  @per_page 999_999

  @default_assigns %{
    description:
      "Select one of your gallery photos that best showcases this product - your client will use this as a starting point, and can customize their product further in the editor.",
    favorites_filter: false,
    page: 0,
    page_title: "Product Preview",
    preview_photo_id: nil,
    selected: false
  }

  def preload([%{gallery_id: gallery_id, product_id: product_id} = assigns | _]) do
    gallery = Galleries.get_gallery!(gallery_id)
    product = GalleryProducts.get(id: to_integer(product_id))
    preview = GalleryProducts.get(id: product_id, gallery_id: gallery_id)
    photos = Galleries.get_gallery_photos(gallery_id)

    [
      Map.merge(assigns, %{
        gallery: gallery,
        product: product,
        preview: preview,
        photo: preview.preview_photo,
        favorites_count: Galleries.gallery_favorites_count(gallery),
        frame_id: preview.category_id,
        category: preview.category,
        title: "#{product.category.name} preview",
        photos: photos
      })
    ]
  end

  def preload([%{gallery_id: gallery_id, photo_id: photo_id} = assigns | _]) do
    gallery = Galleries.get_gallery!(gallery_id)
    photo = Repo.get(Photo, photo_id)
    photos = Galleries.get_gallery_photos(gallery_id)
    photo_id = photo.id

    [
      Map.merge(assigns, %{
        gallery: gallery,
        photo: photo,
        photo_id: photo_id,
        favorites_count: Galleries.gallery_favorites_count(gallery),
        title: nil,
        photos:
          photos
          |> Enum.reject(fn
            %{id: ^photo_id} -> true
            _ -> false
          end)
      })
    ]
  end

  @impl true
  def update(assigns, socket) do
    socket
    |> stream_configure(:photos_new, dom_id: &"photos_new-#{&1.uuid}")
    |> assign(assigns)
    |> assign(Enum.into(assigns, @default_assigns))
    |> assign(:has_more_photos, assigns.photos |> length > @per_page)
    |> stream(:photos_new, assigns.photos)
    |> ok()
  end

  @impl true
  def handle_event(
        "click",
        %{"preview_photo_id" => preview_photo_id},
        socket
      ) do
    preview_photo_id = to_integer(preview_photo_id)

    socket
    |> assign(
      preview_photo_id: preview_photo_id,
      selected: true,
      photo: Galleries.get_photo(preview_photo_id)
    )
    |> push_event("reload_grid", %{})
    |> noreply
  end

  @impl true
  def handle_event(
        "save",
        _,
        %{
          assigns: %{
            preview_photo_id: preview_photo_id,
            frame_id: frame_id,
            product_id: product_id,
            gallery: %{id: gallery_id},
            title: title
          }
        } = socket
      ) do
    [frame_id, preview_photo_id, product_id, gallery_id] =
      Enum.map(
        [frame_id, preview_photo_id, product_id, gallery_id],
        fn x -> to_integer(x) end
      )

    result = GalleryProducts.get(id: to_integer(product_id), gallery_id: to_integer(gallery_id))

    if result != nil do
      result
      |> GalleryProducts.upsert_gallery_product(%{
        preview_photo_id: preview_photo_id,
        category_id: frame_id
      })

      send(self(), {:save, %{title: title}})
    end

    socket |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        _,
        %{
          assigns: %{
            preview_photo_id: preview_photo_id,
            photo_id: photo_id,
            parent_pid: parent_pid
          }
        } = socket
      ) do
    send(
      parent_pid,
      {:confirm_event, "replace_purchased_photo",
       %{new_photo_id: preview_photo_id, old_photo_id: photo_id}}
    )

    socket |> noreply()
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
        photos={@photos}
        streams={@streams}
        selected={@selected}
        myself={@myself}
        title={@title}>
          <%= if @title do %>
            <div class="flex items-start justify-center row-span-2 previewImg">
              <.framed_preview category={@category} photo={@photo} id="framed-edit-preview" />
            </div>
          <% else %>
            <div class="flex items-start justify-center row-span-2 previewImg">
              <.framed_preview  photo={@photo} id="framed-edit-preview" />
            </div>
          <% end %>
      </.preview>
    </div>
    """
  end

  defdelegate framed_preview(assigns), to: TodoplaceWeb.GalleryLive.FramedPreviewComponent
end
