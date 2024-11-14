defmodule TodoplaceWeb.Live.Pricing do
  @moduledoc false
  use TodoplaceWeb, :live_view
  import TodoplaceWeb.Live.User.Settings, only: [settings_nav: 1]

  @impl true
  def mount(_params, _session, socket) do
    socket |> assign(:page_title, "Settings") |> assign_categories() |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_nav socket={@socket} live_action={@live_action} current_user={@current_user} container_class="sm:pb-0 pb-28">
      <div class="my-5">
        <h1 class="text-2xl font-bold">Gallery Store Pricing</h1>

        <p class="max-w-2xl my-2">
          Customize markup pricing for products clients can purchase through you.
        </p>
      </div>

      <hr class="mb-7"/>

      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-8">
      <%= for %{name: name, icon: icon, id: id} <- @categories do %>
        <.live_link to={~p"/pricing/categories/#{id}"} class="block p-5 border rounded">
          <div class="w-full rounded aspect-square bg-base-200">
            <div class="flex items-center justify-center"><.icon name={icon} class="w-1/3 text-blue-planning-300" /></div>
          </div>

          <h2 class="pt-3 text-2xl font-bold"><%= name %></h2>
        </.live_link>
      <% end %>
      </div>
    </.settings_nav>
    """
  end

  @impl true
  def handle_event("intro_js" = event, params, socket),
    do: TodoplaceWeb.LiveHelpers.handle_event(event, params, socket)

  defp assign_categories(socket) do
    socket |> assign(categories: Todoplace.WHCC.categories())
  end
end
