defmodule TodoplaceWeb.GalleryLive.Photos.ThumbnailPhoto do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Phoenix.LiveView.JS

  import TodoplaceWeb.GalleryLive.Photos.Photo.Shared, only: [photo: 1]

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex item flex-col">
      <div class="flex bg-gray-200 h-[130px]">
        <div id={"item-#{@id}"} class="relative cursor-pointer toggle-item item-content preview">
          <div class="galleryItem toggle-parent">
            <div
              id={"photo-#{@id}"}
              class="galleryItem"
              phx-click={toggle_border(@id)}
              phx-click-away={JS.remove_class("item-border", to: "#item-#{@id}")}>
                <.photo
                  target={@component}
                  preview={@photo.preview_url}
                  photo_id={@photo.id}
                  url={preview_url(@photo, proofing_client_view?: false)}
                />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_border(js \\ %JS{}, id) do
    js
    |> JS.dispatch("click", to: "#photo-#{id} > img")
    |> JS.add_class("item-border", to: "#item-#{id}")
  end
end
