defmodule TodoplaceWeb.Live.ClientLive.ClientViewComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.LiveModal, only: [close_x: 1]
  import Phoenix.Component

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dialog modal">
      <.close_x />

      <h1 class="text-3xl font-bold mb-4">
        View client
      </h1>

      <div class="flex items-center">
        <.icon name="client-icon" class="text-blue-planning-300 mr-1 w-6 h-6" />
        <span class="text-black font-bold">Name: </span>
        <span class="text-black ml-2"><%= @client.name %></span>
      </div>

      <%= if @client.phone do %>
        <a href={"tel:#{@client.phone}"} class="flex items-center mt-2">
          <.icon name="phone" class="text-blue-planning-300 mr-2 w-6 h-6" />
          <span class="text-black font-bold">Phone: </span>
          <span class="text-black ml-2"><%= @client.phone %></span>
        </a>
      <% end %>
      <div class="flex items-center mt-2 hover:cursor-pointer">
        <.icon name="envelope" class="text-blue-planning-300 mr-2 w-6 h-6" />
        <span class="text-black font-bold">Email: </span>
        <span class="text-black ml-2"><%= @client.email %></span>
      </div>
      <%= if @client.address do %>
        <div class="flex items-center mt-2">
          <.icon name="address" class="text-blue-planning-300 mr-1 w-6 h-6" />
          <span class="text-black font-bold">Address: </span>
          <span class="text-black ml-2"><%= @client.address %></span>
        </div>
      <% end %>

      <button class="w-full mt-6 font-semibold btn-primary text-lg flex items-center justify-center gap-2" phx-click="edit-client" phx-value-id={@client.id} phx-target={@myself}>
        Edit <.icon name="external-link" class="text-white w-4 h-4" />
      </button>
      <button class="w-full mt-2 border border-current p-3 rounded-lg font-semibold text-lg" phx-click="modal" phx-value-action="close">
        Close
      </button>
    </div>
    """
  end

  @impl true
  def handle_event(
        "edit-client",
        %{"id" => id},
        socket
      ) do
    socket
    |> redirect(to: "/clients/#{id}?edit=true")
    |> noreply()
  end

  def open(%{assigns: %{current_user: current_user}} = socket, client \\ nil) do
    socket |> open_modal(__MODULE__, %{current_user: current_user, client: client})
  end
end
