defmodule TodoplaceWeb.GalleryLive.ClientMenuComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.Live.Profile.Shared, only: [photographer_logo: 1]
  import TodoplaceWeb.GalleryLive.Shared, only: [assign_checkout_routes: 1]

  alias Todoplace.Profiles
  alias Phoenix.LiveView.JS

  @defaults %{
    cart_count: 0,
    cart_route: nil,
    cart: true,
    is_proofing: false,
    client_email: nil,
    credits_available: false,
    open_profile_logout?: false
  }

  @menu_items ["HOME", "MY ORDERS"]
  # To add back Help page, just add "Help" to the list above

  def update(assigns, socket) do
    socket
    |> assign(Map.merge(@defaults, assigns))
    |> then(fn %{assigns: %{gallery: gallery}} = socket ->
      socket
      |> assign(:organization, gallery.job.client.organization)
    end)
    |> assign_checkout_routes()
    |> ok()
  end

  def handle_event(
        "profile_logout",
        _,
        %{assigns: %{open_profile_logout?: open_profile_logout?}} = socket
      ) do
    socket
    |> assign(open_profile_logout?: !open_profile_logout?)
    |> noreply()
  end

  def get_menu_items(assigns) do
    assigns
    |> get_items_paths()
    |> Enum.with_index()
    |> Enum.map(fn {path, i} -> %{title: Enum.at(@menu_items, i), path: path} end)
  end

  # TODO: handle me: (checkout routes)
  def get_items_paths(%{checkout_routes: checkout_routes, gallery: gallery}) do
    help_path = extract_organization(gallery) |> Profiles.public_url()
    [checkout_routes.home_page, checkout_routes.orders, help_path]
  end

  def cart_wrapper(assigns) do
    ~H"""
    <%= if @count > 0 do %>
      <.link navigate={@route} title="cart" class="block"><%= render_slot(@inner_block) %></.link>
    <% else %>
      <div title="cart"><%= render_slot(@inner_block) %></div>
    <% end %>
    """
  end

  defp hamburger(:open),
    do: JS.remove_class("hidden", to: "#gallery-nav") |> JS.dispatch("phx:scroll:lock")

  defp hamburger(:close),
    do: JS.add_class("hidden", to: "#gallery-nav") |> JS.dispatch("phx:scroll:unlock")

  defp extract_organization(%{job: %{client: %{organization: organization}}}), do: organization
end
