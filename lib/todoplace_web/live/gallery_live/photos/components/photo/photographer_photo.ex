defmodule TodoplaceWeb.GalleryLive.Photos.PhotographerPhoto do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Todoplace.{Photos, Cart}
  import TodoplaceWeb.GalleryLive.LoaderIcon
  import TodoplaceWeb.GalleryLive.Photos.Photo.Shared, only: [js_like_click: 2]

  @impl true
  def update(%{photo: %{done?: false} = photo} = assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(is_purchased: false)
    |> assign(:inserted_photo?, Map.get(photo, :inserted_at))
    |> assign(:photo_id, String.split("#{photo.id}", "-") |> List.last())
    |> ok
  end

  @impl true
  def update(%{photo: photo, gallery_id: gallery_id} = assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(is_purchased: Cart.digital_purchased?(%{id: gallery_id}, photo))
    |> assign(:inserted_photo?, Map.get(photo, :inserted_at))
    |> assign(:photo_id, String.split("#{photo.id}", "-") |> List.last())
    |> ok
  end

  def preview(assigns) do
    ~H"""
    <%= if @preview_url do %>
      <div class="relative">
        <img
          class="object-contain aspect-[6/4] max-h-full w-full"
          src={preview_url(@photo, proofing_client_view?: false)}
          loading="lazy"
          alt=""
        />
        <%= if @is_purchased do %>
          <div class="absolute bottom-2 left-2 bg-white pb-1 pt-0.5 text-blue-planning-300 rounded-md px-2">
            Purchased
          </div>
        <% end %>
      </div>
    <% else %>
      <%= if Map.get(@photo, :done?) == false do %>
        <div class="PhotoLoader grid place-items-center text-white absolute z-10 top-0 left-0 h-full w-full bg-gray-600/30 backdrop-blur-[1px]">
          <div class="bg-white rounded-full py-1 px-2 js--photoState hidden flex items-center gap-4 absolute">
            <.loader_icon id={"loader_id-#{@id}"} />
            <div class="js--photoContent z-10 text-xs font-bold text-blue-planning-300"></div>
          </div>
          <progress
            class="progress max-w-full px-2 absolute z-10 [&::-webkit-progress-bar]:rounded-lg [&::-webkit-progress-value]:rounded-lg [&::-webkit-progress-bar]:bg-white [&::-webkit-progress-value]:bg-blue-planning-300 [&::-moz-progress-bar]:bg-blue-planning-300 transition-all"
            value="0"
            max="100"
          >
            0%
          </progress>
        </div>
        <div
          class="object-contain aspect-[6/4] max-h-full min-h-[100px] w-full"
          alt=""
        />
      <% else %>
        <div class="PhotoLoader grid place-items-center text-white absolute z-10 top-0 left-0 h-full w-full bg-gray-600/30 backdrop-blur-[1px]">
          <div class="flex gap-2 justify-center p-1 bg-white rounded-full">
            <.icon class="animate-spin w-5 h-5 text-blue-planning-300" name="loader" />
            <p class="text-blue-planning-300 text-[12px] font-bold text-center flex-shrink-0">
              Generating preview...
            </p>
          </div>
        </div>
        <img
          src={Todoplace.Photos.original_url(@photo)}
          class="object-contain aspect-[6/4] max-h-full w-full"
          loading="lazy"
        />
      <% end %>
    <% end %>
    """
  end

  defp ul(assigns) do
    ~H"""
    <ul class="absolute hidden bg-white pl-1 py-1 rounded-md popover-content meatballsdropdown w-40 overflow-visible z-30">
      <%= for li <- @entries do %>
        <li class="flex items-center hover:bg-blue-planning-100 hover:rounded-md">
          <div class="hover-drop-down" phx-click={li.event} phx-value-photo_id={@photo.id}>
            <%= li.title %>
          </div>
        </li>
      <% end %>
      <li class="flex items-center hover:bg-blue-planning-100 hover:rounded-md">
        <button
          class="hover-drop-down"
          phx-click="download-photo"
          phx-target={@myself}
          phx-value-uri={
            ~p"/gallery/#{@client_link_hash}/photos/#{@photo.id}/download"
          }
        >
          Download photo
        </button>
      </li>
    </ul>
    """
  end

  defp meatball(album, show_products) do
    album
    |> case do
      %{is_client_liked: false} ->
        [
          {"set_album_thumbnail_popup", "Set as album thumbnail"},
          {"remove_from_album_popup", "Remove from album"}
        ]

      _ ->
        [{"photo_view", "View"}]
    end
    |> then(fn
      entries when show_products == true ->
        entries ++ [{"photo_preview_pop", "Set as product preview"}]

      entries ->
        entries
    end)
    |> Enum.map(fn {event, title} -> %{event: event, title: title} end)
  end

  @impl true
  def handle_event("like", %{"id" => id}, socket) do
    {:ok, photo} = Photos.toggle_photographer_liked(id)

    send(self(), {:update_photo_liked, photo})
    socket |> noreply()
  end

  defdelegate handle_event(event, params, socket), to: TodoplaceWeb.GalleryLive.Shared
end
