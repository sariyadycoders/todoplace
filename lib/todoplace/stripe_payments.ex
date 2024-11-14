defmodule Todoplace.StripePayments do
  @moduledoc false

  alias Todoplace.Payments

  @behaviour Payments

  @impl Payments
  defdelegate create_session(params, opts), to: Stripe.Session, as: :create

  @impl Payments
  defdelegate retrieve_session(id, opts), to: Stripe.Session, as: :retrieve

  @impl Payments
  defdelegate expire_session(id, opts), to: Stripe.Session, as: :expire

  @impl Payments
  defdelegate retrieve_account(account_id, opts), to: Stripe.Account, as: :retrieve

  @impl Payments
  defdelegate create_account(params, opts), to: Stripe.Account, as: :create

  @impl Payments
  def create_billing_portal_session(params), do: Stripe.BillingPortal.Session.create(params)

  @impl Payments
  def setup_intent(params, opts),
    do: Stripe.SetupIntent.create(params, opts)

  @impl Payments
  def retrieve_payment_intent(intent_id, opts),
    do: Stripe.PaymentIntent.retrieve(intent_id, %{}, opts)

  @impl Payments
  def cancel_payment_intent(intent_id, opts),
    do: Stripe.PaymentIntent.cancel(intent_id, %{}, opts)

  @impl Payments
  def capture_payment_intent(intent_id, opts),
    do: Stripe.PaymentIntent.capture(intent_id, %{}, opts)

  @impl Payments
  defdelegate create_customer(params, opts), to: Stripe.Customer, as: :create

  @impl Payments
  defdelegate update_customer(id, params, opts), to: Stripe.Customer, as: :update

  @impl Payments
  defdelegate retrieve_customer(id, opts), to: Stripe.Customer, as: :retrieve

  @impl Payments
  defdelegate update_subscription(id, params, opts), to: Stripe.Subscription, as: :update

  @impl Payments
  defdelegate retrieve_subscription(id, opts), to: Stripe.Subscription, as: :retrieve

  @impl Payments
  defdelegate create_subscription(id, opts), to: Stripe.Subscription, as: :create

  @impl Payments
  defdelegate create_subscription_schedule(id, opts), to: Stripe.SubscriptionSchedule, as: :create

  @impl Payments
  defdelegate list_prices(params), to: Stripe.Price, as: :list

  @impl Payments
  defdelegate list_promotion_codes(params), to: Stripe.PromotionCode, as: :list

  @impl Payments
  defdelegate construct_event(body, stripe_signature, signing_secret), to: Stripe.Webhook

  @impl Payments
  defdelegate create_account_link(params, opts), to: Stripe.AccountLink, as: :create

  @impl Payments
  defdelegate create_invoice(params, opts), to: Stripe.Invoice, as: :create

  @impl Payments
  defdelegate finalize_invoice(id, params, opts), to: Stripe.Invoice, as: :finalize

  @impl Payments
  defdelegate create_invoice_item(params, opts), to: Stripe.Invoiceitem, as: :create

  @impl Payments
  defdelegate void_invoice(id, opts), to: Stripe.Invoice, as: :void
end
