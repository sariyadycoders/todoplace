defmodule TodoplaceWeb.StripeOnboardingComponent do
  @moduledoc false

  use TodoplaceWeb, :live_component
  alias Todoplace.Payments

  require Logger

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Enum.into(%{
        class: nil,
        container_class: nil,
        org_card_id: nil
      })

    ~H"""
    <div class={@container_class}>
      <.form :let={_} for={%{}} as={:stripe} phx-submit="link-stripe" phx-target={@myself}>
        <%= case @stripe_status do %>
          <% :loading -> %>
            <div class="flex items-center justify-center w-full m-2 text-xs">
              <div class="w-3 h-3 mr-2 rounded-full opacity-75 bg-blue-planning-300 animate-ping"></div>
              Loading...
            </div>

          <% :error -> %>
            <button type="submit" phx-disable-with="Retry Stripe account" class={@class} {add_card_hook(@org_card_id)}>
              Retry Stripe account
            </button>
            <em class={"block pt-1 text-xs text-red-sales-300 " <> @error_class}>Error accessing your Stripe information.</em>

          <% :no_account -> %>
            <button type="submit" phx-disable-with="Set up Stripe" class={@class} {add_card_hook(@org_card_id)}>
              Set up Stripe
            </button>

          <% :missing_information -> %>
            <button type="submit" phx-disable-with="Stripe Account incomplete" class={@class} {add_card_hook(@org_card_id)}>
              Stripe Account incomplete
            </button>
            <em class="block pt-1 text-xs text-center text-red-sales-300">Please provide missing information.</em>

          <% :pending_verification -> %>
            <button type="submit" phx-disable-with="Check Stripe status" class={@class} {add_card_hook(@org_card_id)}>
              Check Stripe status
            </button>
            <em class="block pt-1 text-xs text-center">Your account has been created. Please wait for Stripe to verify your information.</em>

          <% :charges_enabled -> %>
            <a href="https://dashboard.stripe.com/" target="_blank" rel="noopener noreferrer" class={"block #{@class}"} {add_card_hook(@org_card_id)}>
              Go to Stripe account
            </a>

        <% end %>
      </.form>

    </div>
    """
  end

  defp add_card_hook(nil), do: []

  defp add_card_hook(org_card_id) do
    [
      data_status: "viewed",
      id: to_string(org_card_id),
      phx_hook: "CardStatus"
    ]
  end

  @impl true
  def handle_event("card_status", params, socket),
    do: TodoplaceWeb.HomeLive.Index.handle_event("card_status", params, socket)

  @impl true
  def handle_event(
        "link-stripe",
        %{},
        %{assigns: %{current_user: current_user, return_url: return_url}} = socket
      ) do
    refresh_url = url(~p"/users/settings/stripe-refresh")

    case Payments.custom_link(current_user, refresh_url: refresh_url, return_url: return_url) do
      {:ok, url} ->
        socket |> redirect(external: url) |> noreply()

      {:error, error} ->
        Logger.error(error)
        socket |> put_flash(:error, "Couldn't link stripe account.") |> noreply()
    end
  end
end
