defmodule TodoplaceWeb.SuccessComponent do
  @moduledoc false

  use TodoplaceWeb, :live_component

  @default_assigns %{
    close_label: "Close",
    close_class: "",
    success_event: nil,
    success_label: "Go to item",
    success_class: "btn-primary font-semibold text-lg",
    subtitle: nil,
    for: nil
  }

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(Enum.into(assigns, @default_assigns))
    |> ok()
  end

  @impl true
  def render(assigns) do
    assigns = Enum.into(assigns, %{class: "bg-white p-6 rounded-lg"})

    ~H"""
    <div class={@class <> " max-w-[642px]"}>
      <h1 class="font-bold text-3xl">
        <%= @title %>
      </h1>

      <%= if @subtitle do %>
        <p class="pt-4 whitespace-pre-wrap font-medium text-lg"><%= @subtitle %></p>
      <% end %>

      <div style="border-radius: 10px" class="flex flex-col px-6 pt-6 mt-4 bg-neutral-200 text-lg">
        <div class="mb-4">
          <.description for={@for} />
        </div>
        <div class="grid grid-cols-4">
          <.inner_section socket={@socket} for={@for} />
        </div>
      </div>

      <%= if @success_event do %>
        <button
          class={"w-full mt-6 " <> @success_class}
          title={@success_label}
          type="button"
          phx-click={@success_event}
          phx-disable-with="Saving&hellip;"
          phx-target={@myself}
        >
          <%= @success_label %>
        </button>
      <% end %>

      <button
        class={"w-full mt-6 border border-current p-3 rounded-lg font-semibold text-lg " <> @close_class}
        type="button"
        phx-click="modal"
        phx-value-action="close"
      >
        <%= @close_label %>
      </button>
    </div>
    """
  end

  @impl true
  def handle_event(event, %{}, %{assigns: %{parent_pid: parent_pid, payload: payload}} = socket) do
    send(parent_pid, {:success_event, event, payload})

    socket |> noreply()
  end

  @impl true
  def handle_event(event, %{}, %{assigns: %{parent_pid: parent_pid}} = socket) do
    send(parent_pid, {:success_event, event})

    socket |> noreply()
  end

  @spec open(Phoenix.LiveView.Socket.t(), %{
          optional(:close_label) => binary,
          optional(:close_class) => binary,
          optional(:success_event) => any,
          optional(:success_label) => binary,
          optional(:success_class) => binary,
          optional(:class) => binary | nil,
          optional(:subtitle) => binary,
          optional(:payload) => map,
          optional(:for) => atom() | binary(),
          title: binary
        }) :: Phoenix.LiveView.Socket.t()
  def open(socket, assigns) do
    socket
    |> open_modal(__MODULE__, Map.put(assigns, :parent_pid, self()))
  end

  defp description(%{for: "proofing"} = assigns) do
    ~H"""
    You can handle all the key steps of proofing your photos for your client right from this album, and
    create additional proofing albums within this gallery if you need more.
    """
  end

  defp description(assigns) do
    ~H"""
    <span class="font-bold">We've created a client and a job under the hood for you.</span>
    A job is the hub for your gallery,
    transaction history, and communication with your client. Don't forget you can
    use Todoplace to handle everything!
    """
  end

  defp inner_section(%{for: "proofing"} = assigns) do
    ~H"""
    <%= for path <- ["proofing_gallery_left.png", "proofing_gallery_right.png"] do %>
      <.image socket={@socket} path={"/images/#{path}"} />
    <% end %>
    """
  end

  defp inner_section(assigns) do
    ~H"""
    <div class="flex justify-center items-center">
      <.icon name="rupees" class="w-8 h-8" />
    </div>

    <div class="col-span-2 row-span-2">
      <.image socket={@socket} path="/images/gallery_created.png" />
    </div>

    <%= for {name, class} <- [{"phone", ""}, {"cart", "pb-6"}, {"envelope", "pb-6"}] do %>
      <.inner_section_icon name={name} class={class} />
    <% end %>
    """
  end

  defp inner_section_icon(assigns) do
    assigns = Enum.into(assigns, %{class: ""})

    ~H"""
    <div class={"flex justify-center items-center #{@class}"}>
      <.icon name={@name} style="color: rgba(137, 137, 137, 0.2)" class="w-8 h-8" />
    </div>
    """
  end

  defp image(assigns) do
    ~H"""
    <div class="col-span-2 row-span-2">
      <img src={static_path(@socket, @path)} />
    </div>
    """
  end
end
