defmodule Todoplace.Orders.Confirmations do
  @moduledoc """
    Context module for handling order payments.

    These are the steps that occur when we hear from stripe about an order payment from a photographer or their client.

    See also Todoplace.Cart.Checkouts for the steps that come before this in the ordering process.
  """

  alias Todoplace.{
    Cart.Order,
    Cart.Product,
    Cart.OrderNumber,
    Galleries,
    Intents,
    Invoices,
    Invoices.Invoice,
    Payments,
    Repo,
    WHCC,
    OrganizationCard,
    EmailAutomationSchedules
  }

  import Todoplace.Zapier.GalleryOrders, only: [gallery_order_whcc_update: 1]

  import Ecto.Query, only: [from: 2]
  import Ecto.Multi, only: [new: 0, put: 3, update: 3, run: 3, merge: 2, append: 2, insert: 3]

  @doc """
  Handles a stripe session.

  1. query for order and connect account
  1. make sure the order isn't already paid
  1. maybe fetch the session
  1. update intent
  1. is client paid up?
    1. is the order all paid for?
      1. capture the stripe funds
      1. confirm with whcc
    1. photographer still owes?
      1. finalize photographer invoice
  """
  @spec handle_session(Stripe.Session.t()) ::
          {:ok, Order.t(), :confirmed | :already_confirmed} | {:error, any()}
  def handle_session(
        %Stripe.Session{client_reference_id: "order_number_" <> order_number} = session
      ) do
    do_confirm_order(order_number, &Ecto.Multi.put(&1, :session, session))
  end

  @spec handle_session(String.t(), String.t()) ::
          {:ok, Order.t(), :confirmed | :already_confirmed} | {:error, any()}
  def handle_session(order_number, stripe_session_id) do
    do_confirm_order(
      order_number,
      &Ecto.Multi.run(&1, :session, __MODULE__, :fetch_session, [stripe_session_id])
    )
  end

  @doc """
  Handles a stripe invoice.

  1. query for existing invoice
  1. updates existing invoice with stripe info
  1. is order all paid for?
      1. capture client funds
      1. confirm with whcc
  """
  @spec handle_invoice(Stripe.Invoice.t()) :: {:ok, map()} | {:error, atom(), any(), map()}
  def handle_invoice(invoice) do
    new()
    |> put(:stripe_invoice, invoice)
    |> run(:invoice, &load_invoice/2)
    |> update(:updated_invoice, &update_invoice_changeset/1)
    |> merge(fn
      %{updated_invoice: %{order: %{intent: intent} = order, status: :paid}} ->
        new()
        |> run(:confirm_order, fn _, _ -> confirm_order(order) end)
        |> update(:order, Order.whcc_confirmation_changeset(order))
        |> append(handle_capture(intent, order))

      _ ->
        new()
    end)
    |> Repo.transaction()
  end

  @doc """
    Handles intent cancelled event.
    Most likely because the clock ran out on the hold.

    1. query for intent
    1. update intent
    1. is there an unpaid invoice?
       1. cancel invoice

  """
  @spec handle_intent(Stripe.PaymentIntent.t()) :: any()
  def handle_intent(intent) do
    new()
    |> put(:stripe_intent, intent)
    |> update(:intent, &update_intent/1)
    |> run(:order, &load_order/2)
    |> run(:open_invoice, &load_open_invoice/2)
    |> merge(fn
      %{open_invoice: nil} ->
        new()

      %{open_invoice: invoice} ->
        new()
        |> put(:invoice, invoice)
        |> run(:void_stripe_invoice, &void_invoice/2)
        |> update(:voided_invoice, &update_invoice/1)
    end)
    |> Repo.transaction()
  end

  @doc """
    Handles notifying zapier of order status
    for realtime notifications
  """
  def send_zapier_notification(
        %{
          id: id,
          number: number,
          gallery_id: gallery_id,
          whcc_order: %{
            confirmation_id: confirmation_id,
            confirmed_at: confirmed_at,
            orders: whcc_orders
          },
          gallery: %{job: %{client: %{organization: organization}}}
        } = order,
        status
      ) do
    gallery_order_whcc_update(%{
      order_id: id,
      order_number: number,
      order_total: Order.product_total(order),
      gallery_id: gallery_id,
      photographer_email: organization.user.email,
      whcc_status: status,
      whcc_confirmation_id: confirmation_id,
      whcc_confirmed_at: confirmed_at,
      whcc_orders: Enum.map(whcc_orders, &Map.from_struct/1),
      whcc_environment: Keyword.get(Application.get_env(:todoplace, :whcc), :url)
    })
  end

  def send_zapier_notification(_, _), do: nil

  defp load_open_invoice(repo, %{order: order}) do
    {:ok, order |> Invoices.open_invoice_for_order_query() |> repo.one()}
  end

  defp void_invoice(_repo, %{invoice: %{stripe_id: invoice_stripe_id}}) do
    Payments.void_invoice(invoice_stripe_id)
  end

  defp update_invoice(%{invoice: invoice, void_stripe_invoice: stripe_invoice}) do
    Invoices.changeset(invoice, stripe_invoice)
  end

  defp update_intent(%{stripe_intent: stripe_intent}), do: Intents.update_changeset(stripe_intent)

  defp handle_capture(nil, _), do: new()

  defp handle_capture(intent, order) do
    new() |> run(:capture, fn _, _ -> capture(intent, stripe_options(order)) end)
  end

  defp do_confirm_order(order_number, session_fn) do
    new()
    |> put(:order_number, order_number)
    |> run(:order, &load_order/2)
    |> run(:stripe_options, &stripe_options/2)
    |> session_fn.()
    |> run(:client_paid, &check_paid/2)
    |> update(:place_order, &place_order/1)
    |> run(:intent, &update_intent/2)
    |> run(:photographer_owes, &photographer_owes/2)
    |> merge(fn
      %{order: %{products: [_ | _]} = order, photographer_owes: %{amount: 0}} = multi ->
        new()
        |> run(:confirm_order, fn _, _ -> confirm_order(order) end)
        |> update(:confirmed_order, Order.whcc_confirmation_changeset(order))
        |> run(:capture, fn _, _ -> capture(multi) end)

      %{order: %{products: []}} = multi ->
        run(new(), :capture, fn _, _ -> capture(multi) end)

      %{order: order, photographer_owes: photographer_owes} = multi ->
        new()
        |> run(:stripe_invoice, fn _, _ -> create_stripe_invoice(order, photographer_owes) end)
        |> insert(:invoice, &insert_invoice_changeset(&1, order))
        |> run(:confirm_order, fn _, _ -> confirm_order(order) end)
        |> update(:confirmed_order, Order.whcc_confirmation_changeset(order))
        |> run(:capture, fn _, _ -> capture(multi) end)
    end)
    |> run(:insert_card, fn _repo, %{order: order} ->
      OrganizationCard.insert_for_proofing_order(order)
    end)
    |> run(:insert_orders_emails, fn _repo, %{order: order} ->
      EmailAutomationSchedules.insert_gallery_order_emails(nil, order)
    end)
    |> Repo.transaction()
    |> case do
      {:error, :client_paid, _, %{order: order}} ->
        {:ok, order, :already_confirmed}

      {:ok, %{place_order: order}} ->
        send_zapier_notification(order, "order_placed")

        {:ok, order, :confirmed}

      {:error, _, _, %{session: %{payment_intent: intent_id}, stripe_options: stripe_options}} =
          error ->
        Payments.cancel_payment_intent(intent_id, stripe_options)
        error

      other ->
        other
    end
  end

  defp photographer_owes(_repo, %{order: %{whcc_order: nil} = order}),
    do: {:ok, Money.new(0, order.currency)}

  defp photographer_owes(_repo, %{
         intent: %{application_fee_amount: nil, amount: amount},
         order: %{currency: currency} = order
       }) do
    {:ok, calculate_total_costs(order) |> Money.add(stripe_fee(amount, currency))}
  end

  defp photographer_owes(_repo, %{
         intent: %{application_fee_amount: _application_fee_amount, amount: amount},
         order: %{currency: currency} = order
       }) do
    actual_costs_and_fees =
      calculate_total_costs(order) |> Money.add(actual_stripe_fee(amount, currency))

    costs_and_fees =
      calculate_total_costs(order)
      |> stripe_fee(currency)
      |> Money.add(calculate_total_costs(order))

    case Money.cmp(amount, actual_costs_and_fees) do
      :lt -> {:ok, Money.subtract(costs_and_fees, amount)}
      :gt -> {:ok, Money.new(0, currency)}
      _ -> {:ok, Money.new(0, currency)}
    end
  end

  defp calculate_total_costs(order) do
    order
    |> Product.total_cost()
    |> Money.add(Todoplace.Cart.total_shipping(order))
  end

  # stripe's actual formula to calculate fee
  # After transactions of $1million, stripe processing fee is discounted,
  # and we will need to tweak this formula in future.
  defp actual_stripe_fee(amount, currency) do
    amount
    |> Money.multiply(2.9 / 100)
    |> Money.add(Money.new(30, currency))
  end

  # our formula to calculate fee to be on safe side
  defp stripe_fee(amount, currency) do
    amount
    |> Money.multiply(2.9 / 100)
    |> Money.add(Money.new(70, currency))
  end

  defp place_order(%{order: order}), do: Order.placed_changeset(order)

  defp load_order(repo, %{order_number: order_number}) do
    load_order(repo, OrderNumber.from_number(order_number))
  end

  defp load_order(repo, %{intent: %{order_id: order_id}}) do
    load_order(repo, order_id)
  end

  defp load_order(repo, order_id) do
    from(order in Order,
      where: order.id == ^order_id,
      preload: [
        products: :whcc_product,
        digitals: :photo,
        gallery: [organization: :user]
      ]
    )
    |> repo.one()
    |> case do
      nil -> {:error, "cannot load order"}
      order -> {:ok, order}
    end
  end

  defp stripe_options(_, %{order: order}) do
    case order do
      %{gallery: %{organization: %{stripe_account_id: stripe_account_id}}} ->
        {:ok, connect_account: stripe_account_id}

      _ ->
        {:error, "no connect account"}
    end
  end

  defp stripe_options(%{gallery: %{organization: %{stripe_account_id: stripe_account_id}}}),
    do: [connect_account: stripe_account_id]

  defp check_paid(_, %{order: order}) do
    if Todoplace.Orders.client_paid?(order) do
      {:error, true}
    else
      {:ok, false}
    end
  end

  def fetch_session(
        _repo,
        %{order_number: order_number, stripe_options: stripe_options},
        session_id
      ) do
    case Payments.retrieve_session(session_id, stripe_options) do
      {:ok, %{client_reference_id: "order_number_" <> ^order_number} = session} ->
        {:ok, session}

      {:ok, session} ->
        {:error, "unexpected session:\n#{inspect(session)}"}

      error ->
        error
    end
  end

  defp update_intent(_, %{
         session: %{payment_intent: intent_id},
         stripe_options: stripe_options
       }) do
    case Payments.retrieve_payment_intent(intent_id, stripe_options) do
      {:ok, intent} ->
        Todoplace.Intents.update(intent)

      error ->
        error
    end
  end

  defp confirm_order(%Order{
         gallery_id: gallery_id,
         whcc_order: %{confirmation_id: confirmation_id}
       }) do
    gallery_id |> Galleries.account_id() |> WHCC.confirm_order(confirmation_id)
  end

  defp capture(%{intent: intent, stripe_options: stripe_options}) do
    capture(intent, stripe_options)
  end

  defp capture(intent, options) do
    case Todoplace.Intents.capture(intent, options) do
      {:ok, %{status: :succeeded} = intent} ->
        {:ok, intent}

      error ->
        error
    end
  end

  defp load_invoice(repo, %{stripe_invoice: %Stripe.Invoice{id: stripe_id}}) do
    Invoice
    |> repo.get_by(stripe_id: stripe_id)
    |> case do
      nil -> {:error, "no invoice"}
      invoice -> {:ok, repo.preload(invoice, order: [:intent, gallery: :organization])}
    end
  end

  defp load_invoice(repo, %Order{id: order_id}) do
    Invoice
    |> repo.get_by(order_id: order_id)
    |> case do
      nil -> {:error, "no invoice"}
      invoice -> {:ok, invoice}
    end
  end

  defp load_invoice(repo, %{intent: %{order_id: order_id}}),
    do: load_invoice(repo, %Order{id: order_id})

  defp update_invoice_changeset(%{stripe_invoice: stripe_invoice, invoice: invoice}) do
    Invoice.changeset(invoice, stripe_invoice)
  end

  defp create_stripe_invoice(
         %{currency: currency, gallery: %{organization: %{user: user}}} = invoice_order,
         outstanding
       ) do
    Invoices.invoice_user(user, outstanding,
      description: "Outstanding fulfilment charges for order ##{Order.number(invoice_order)}",
      currency: currency
    )
  end

  defp insert_invoice_changeset(%{stripe_invoice: stripe_invoice}, order),
    do: Invoices.changeset(stripe_invoice, order)
end
