defmodule TodoplaceWeb.Live.Admin.WHCCOrdersPricingReport do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: false]
  alias Todoplace.{Orders, Cart, Cart.Product}
  alias Todoplace.WHCC.Order.Created, as: WHCCOrder

  def mount(%{"order_number" => order_number}, _, socket) do
    order =
      Orders.get_order_from_order_number(order_number)
      |> Todoplace.Repo.preload([:intent, :digitals, products: :whcc_product])

    charges = Todoplace.Notifiers.UserNotifier.photographer_payment(order)

    socket
    |> assign(order: order)
    |> assign(photographer_payment: Map.get(charges, :photographer_payment))
    |> assign(photographer_charge: Map.get(charges, :photographer_charge) |> Money.neg())
    |> assign(stripe_fee: Map.get(charges, :stripe_fee) |> Money.neg())
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="w-screen text-xs">
      <table class="w-full table-fixed">
        <tr class="border">
          <th>Client Paid</th>
          <th>Shipping</th>
          <th>Print Cost for Photog</th>
          <th>Discounted Print Cost for Todoplace</th>
          <th>Stripe fee</th>
          <th>Photographer Paid to us</th>
          <th>Photographer's Profit</th>
        </tr>
        <tr class="text-center w-full">
          <td><%= Cart.Order.total_cost(@order) %></td>
          <td><%= Cart.total_shipping(@order) %></td>
          <td><%= print_cost_for_photog(@order) %></td>
          <td><%= print_cost_for_todoplace(@order) %></td>
          <td><%= @stripe_fee %></td>
          <td><%= @photographer_charge %></td>
          <td><%= @photographer_payment %></td>
        </tr>
      </table>
    </div>
    """
  end

  defp print_cost_for_photog(%{products: []}), do: nil

  defp print_cost_for_photog(%{products: _products} = order) do
    order |> Product.total_cost()
  end

  defp print_cost_for_todoplace(%{products: []}), do: nil

  defp print_cost_for_todoplace(%{whcc_order: whcc_order}) do
    whcc_order |> WHCCOrder.total()
  end
end
