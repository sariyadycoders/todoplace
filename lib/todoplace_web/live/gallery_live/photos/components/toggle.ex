defmodule TodoplaceWeb.GalleryLive.Photos.Toggle do
  @moduledoc "Component to toggle selctions and favorites"

  use TodoplaceWeb, :live_component
  import TodoplaceWeb.LiveHelpers

  @impl true
  def update(assigns, socket) do
    socket |> assign(assigns) |> ok()
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Enum.into(%{title_class: ""})

    ~H"""
    <label id={@id} class={"flex items-center lg:order-2 order-1 lg:mr-0 lg:mb-0 cursor-pointer #{@class}"}>
      <div class={"font-sans text-sm #{@title_class}"}><%= @title %></div>
      <div class="relative ml-3">
        <input type="checkbox" class="sr-only" phx-click={@action}>
        <%= if @filter do %>
          <div class="flex w-12 h-6 border rounded-full bg-blue-planning-300 border-base-100"></div>
          <div class="absolute w-4 h-4 rounded-full transition dot right-1 top-1 bg-base-100"></div>
        <% else %>
          <div class="block w-12 h-6 bg-gray-200 border rounded-full border-blue-planning-300"></div>
          <div class="absolute w-4 h-4 rounded-full transition dot left-1 top-1 bg-blue-planning-300"></div>
        <% end %>
      </div>
    </label>
    """
  end

  def toggle(assigns) do
    ~H"""
    <.live_component module={__MODULE__} id={assigns[:id] || "toggle"} {assigns} />
    """
  end
end
