defmodule TodoplaceWeb.Live.FinancesManage.OnlinePaymentViewComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Todoplace.{PaymentSchedule, Cart.Order}

  @impl true
  def update(%{transaction: transaction} = assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(digital_counts: "")
    |> assign(product_counts: "")
    |> assign(digital_total_price: "")
    |> assign(product_total_price: "")
    |> assign(payment_price: "")
    |> assign(payment_type: "")
    |> assign(transaction_is_order: false)
    |> assign(is_offline_payment?: false)
    |> assign(title: "Payment -  Stripe")
    |> assign_defaults(transaction)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col modal-small p-30 text-black">
      <div class="flex items-start justify-between flex-shrink-0">
        <h1 class="text-3xl font-bold">
          <%= @title %>
        </h1>

        <button phx-click="modal" phx-value-action="close" title="close modal" type="button" class="p-2">
          <.icon name="close-x" class="w-3 h-3 stroke-current stroke-2 sm:stroke-1 sm:w-6 sm:h-6"/>
        </button>
      </div>
      <div class="font-bold text-xl mt-3">
        <%= Calendar.strftime(@transaction.updated_at, "%m/%d/%y") %>
      </div>
      <div class="text-base-250 text-xl mb-3 capitalize">
        <%= @client %>
      </div>

      <div class="flex justify-between text-xl font-bold pb-2 border-b-4 border-blue-planning-300">
        <div class="">
          Item
        </div>
        <div>
          Item Total
        </div>
      </div>

      <%= if @transaction_is_order do %>
        <div class="flex justify-between mt-2">
          <div class="">
            Digital line item x <%= @digital_counts %>
          </div>
          <div>
            <%= @digital_total_price %>
          </div>
        </div>
        <div class="flex justify-between mt-2">
          <div class="">
            Product line item x <%= @product_counts %>
          </div>
          <div>
            <%= @product_total_price %>
          </div>
        </div>
        <hr class="my-3"/>
        <div class="flex justify-between font-bold">
          <div class="">
            Total
          </div>
          <div>
            <%= @net_total_price %>
          </div>
        </div>
      <% else %>
        <div class="flex justify-between mt-2">
          <div class="capitalize">
            <%= @payment_type %>
          </div>
          <div>
            <%= @payment_price %>
          </div>
        </div>
        <hr class="my-3"/>
        <div class="flex justify-between font-bold">
          <div class="">
            Total
          </div>
          <div>
            <%= @payment_price %>
          </div>
        </div>
      <% end %>

      <%= if !@is_offline_payment? do %>
        <hr class="my-3"/>
        <div class="text-xl font-bold">
          Stripe Taxes and Fees
        </div>
        <div class="flex justify-between mt-2">
          <div class="">
            Taxes <span class="text-base-250">(if applicable/setup)</span>
          </div>
          <div class="font-bold  ">
            <%= @tax %>
          </div>
        </div>
        <div class="flex justify-between mt-2">
          <div class="">
            Fees
          </div>
          <div class="font-bold">
          <%= @fees %>
          </div>
        </div>
        <hr class="my-3"/>
        <%= if @stripe_payment_intent_id do %>
          <div class="text-base-250">
            Paste this into your <a href={"https://dashboard.stripe.com/#{@current_user.organization.stripe_account_id}/customers/#{@stripe_payment_intent_id}"} target="_blank" class="text-blue-planning-300 underline">Stripe</a> search bar for more details or provide to Todoplace Support
          </div>
          <div class="p-2 border-2 rounded-lg flex items-center justify-between mt-3">
            <div><%= @stripe_payment_intent_id || "-" %></div>
            <button id={"copy-intent-#{@stripe_payment_intent_id}"} class="px-2 py-1 rounded-lg bg-base-200 text-blue-planning-300" data-clipboard-text={@stripe_payment_intent_id} phx-hook="Clipboard">
              Copy
              <div class="z-30 bg-white hidden p-1 text-sm rounded shadow" role="tooltip">
                Copied!
              </div>
            </button>
          </div>
        <% end %>
      <% end %>
      <button phx-click="modal" phx-value-action="close" title="close modal" type="button" class="btn-tertiary mt-3">Close</button>
    </div>
    """
  end

  def open(%{assigns: %{current_user: current_user}} = socket, opts) do
    socket
    |> open_modal(__MODULE__, %{
      assigns: %{
        current_user: current_user,
        transaction: opts.transaction,
        stripe_account_id: opts.stripe_account_id
      }
    })
  end

  defp assign_defaults(socket, %PaymentSchedule{} = transaction) do
    socket =
      if transaction.type != "stripe" do
        socket |> assign(is_offline_payment?: true) |> assign(title: "Payment -  Offline")
      else
        socket
      end

    socket
    |> assign(payment_price: transaction.price)
    |> assign(client: Todoplace.Job.name(transaction.job))
    |> assign(payment_type: transaction.type)
    |> assign_payment_schedule_tax(transaction)
    |> assign_fees_and_intent(transaction)
  end

  defp assign_defaults(socket, %Order{} = transaction) do
    {digital_counts, product_counts, digital_total_price, product_total_price, net_total_price} =
      total_price_for_gallery_order(transaction)

    socket
    |> assign(client: Todoplace.Job.name(transaction.gallery.job))
    |> assign(digital_counts: digital_counts)
    |> assign(product_counts: product_counts)
    |> assign(digital_total_price: digital_total_price)
    |> assign(product_total_price: product_total_price)
    |> assign(net_total_price: net_total_price)
    |> assign(transaction_is_order: true)
    |> assign_gallery_order_taxes(transaction)
    |> assign_fees_and_intent(transaction)
  end

  def total_price_for_gallery_order(%Order{} = transaction) do
    digital_counts = Enum.count(transaction.digitals)
    {digital_total_price, first_price} = subtotal_price(transaction.digitals)

    product_counts = Enum.count(transaction.products)
    {product_total_price, second_price} = subtotal_price(transaction.products)

    total = first_price + second_price

    net_total_price = "$" <> (total |> to_string())

    {digital_counts, product_counts, digital_total_price, product_total_price, net_total_price}
  end

  defp assign_fees_and_intent(socket, %PaymentSchedule{} = transaction) do
    socket
    |> assign(:fees, 0)
    |> assign(:stripe_payment_intent_id, transaction.stripe_payment_intent_id)
  end

  defp assign_fees_and_intent(socket, %Order{} = transaction) do
    if transaction.intent do
      socket
      |> assign(fees: transaction.intent.application_fee_amount)
      |> assign(stripe_payment_intent_id: transaction.intent.stripe_payment_intent_id)
    else
      socket
      |> assign(:fees, 0)
      |> assign(stripe_payment_intent_id: nil)
    end
  end

  defp assign_payment_schedule_tax(
         %{assigns: %{stripe_account_id: stripe_account_id}} = socket,
         transaction
       ) do
    if transaction.stripe_session_id do
      case Todoplace.Payments.retrieve_session(transaction.stripe_session_id,
             connect_account: stripe_account_id
           ) do
        {:ok, session} ->
          socket
          |> assign(tax: session.total_details.amount_tax)

        {:error, _} ->
          socket
          |> assign(tax: 0)
      end
    else
      socket
      |> assign(tax: 0)
    end
  end

  defp assign_gallery_order_taxes(
         %{assigns: %{stripe_account_id: stripe_account_id}} = socket,
         transaction
       ) do
    if transaction.intent do
      case Todoplace.Payments.retrieve_session(transaction.intent.stripe_session_id,
             connect_account: stripe_account_id
           ) do
        {:ok, session} ->
          socket
          |> assign(tax: session.total_details.amount_tax)

        {:error, _} ->
          socket
          |> assign(tax: 0)
      end
    else
      socket
      |> assign(tax: 0)
    end
  end

  defp subtotal_price(product_or_digital) do
    price =
      Enum.reduce(product_or_digital, 0, fn product_or_digital, acc ->
        price_modifications(product_or_digital) + acc
      end)

    {"$" <> (price |> to_string()), price}
  end

  defp price_modifications(product_or_digital) do
    price = Todoplace.Cart.price_display(product_or_digital)

    do_price_modifications(price)
  end

  defp do_price_modifications(%Money{} = price) do
    price
    |> Money.to_string(symbol: false)
    |> String.replace(",", "")
    |> String.to_float()
    |> Float.round(2)
  end

  defp do_price_modifications(_price) do
    0
  end
end
