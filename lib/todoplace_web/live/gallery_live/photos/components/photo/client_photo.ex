defmodule TodoplaceWeb.GalleryLive.Photos.Photo.ClientPhoto do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Todoplace.Photos
  alias TodoplaceWeb.Router.Helpers, as: Routes

  import TodoplaceWeb.GalleryLive.Photos.Photo.Shared

  @impl true
  def update(%{photo: photo} = assigns, socket) do
    socket
    |> assign(
      preview_photo_id: nil,
      component: false,
      client_liked_album: false,
      is_proofing: assigns[:is_proofing] || false,
      client_link_hash: Map.get(assigns, :client_link_hash),
      is_liked: photo.client_liked,
      url: static_path(TodoplaceWeb.Endpoint, "/images/gallery-icon.svg")
    )
    |> assign(assigns)
    |> ok
  end

  @impl true
  def handle_event("like", %{"id" => id}, socket) do
    {:ok, _} = Photos.toggle_liked(id)
    send(self(), :update_client_gallery_state)
    socket |> noreply()
  end

  defp wrapper_style(width, %{aspect_ratio: aspect_ratio}),
    do: "height: #{width / aspect_ratio}px;"
end
