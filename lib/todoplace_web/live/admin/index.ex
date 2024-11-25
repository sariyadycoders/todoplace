defmodule TodoplaceWeb.Live.Admin.Index do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: false]

  use Phoenix.VerifiedRoutes,
    endpoint: TodoplaceWeb.Endpoint,
    router: TodoplaceWeb.Router

  import TodoplaceWeb.LayoutView,
    only: [
      admin_banner: 1
    ]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :class, "border flex items-center justify-center rounded-lg p-8")

    ~H"""
    <header class="p-8 bg-gray-100" phx-hook="showAdminBanner" id="show-admin-banner">
      <h1 class="text-4xl font-bold">Todoplace Admin</h1>
      <.admin_banner socket={@socket} />
    </header>
    <nav class="p-8">
      <ul class="mt-4 font-bold grid gap-10 grid-cols-1 sm:grid-cols-4 text-blue-planning-300">
        <li><.link navigate={~p"/admin/dashboard"} class={@class}>Performance Dashboard</.link></li>

        <li>
          <.link navigate={~p"/admin/categories"} class={@class}>
            Product Category Configuration
          </.link>
        </li>

        <li><.link navigate={~p"/admin/workers"} class={@class}>Run Jobs</.link></li>

        <li>
          <.link navigate={~p"/admin/pricing_calculator"} class={@class}>
            Smart Profit Calculator™ Configuration
          </.link>
        </li>

        <li><.link navigate={~p"/admin/next_up_cards"} class={@class}>Next Up Cards Admin</.link></li>

        <li><.link navigate={~p"/admin/user"} class={@class}>Manage Users</.link></li>

        <li>
          <.link navigate={~p"/admin/user/subscription_report"} class={@class}>
            User Subscription Reconciliation Report
          </.link>
        </li>

        <li>
          <.link navigate={~p"/admin/subscription_pricing"} class={@class}>
            Subscription Pricing
          </.link>
        </li>

        <li>
          <.link navigate={~p"/admin/product_pricing"} class={@class}>Product Pricing Report</.link>
        </li>

        <li>
          <.link navigate={~p"/admin/shipment_details"} class={@class}>Manage Shipment Details</.link>
        </li>

        <li>
          <.link navigate={~p"/admin/automations"} class={@class}>Automations Report Index</.link>
        </li>

        <li>
          <div class="grid border flex items-center justify-center rounded-lg py-4 px-8">
            Current photo Uploaders
            <div class="flex items-center justify-center text-red-500 pt-2">
              <%= TodoplaceWeb.UploaderCache.current_uploaders() %>
            </div>
          </div>
        </li>

        <li>
          <.link navigate={~p"/admin/global_settings"} class={@class}>
            Manage Admin Global Settings
          </.link>
        </li>

        <li>
          <.link navigate={~p"/admin/whcc_orders_report"} class={@class}>WHCC Orders report</.link>
        </li>

        <li><.link navigate={~p"/feature-flags"} class={@class}>Feature Flags</.link></li>

        <li>
          <.link navigate={~p"/admin/automated-emails"} class={@class}>Manage Automated Emails</.link>
        </li>
      </ul>
    </nav>
    """
  end
end
