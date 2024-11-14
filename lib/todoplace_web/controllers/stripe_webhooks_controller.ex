defmodule TodoplaceWeb.StripeWebhooksController do
  use TodoplaceWeb, :controller
  require Logger
  alias Todoplace.{Accounts, Orders, PaymentSchedules, Notifiers.OrderNotifier}

  def connect_webhooks(conn, _params) do
    do_webhook(:connect, conn)
    success_response(conn)
  end

  def app_webhooks(conn, _params) do
    Logger.info("----------reached in app_webhooks")
    do_webhook(:app, conn)
    success_response(conn)
  end

  defp do_webhook(event_type, %Plug.Conn{assigns: %{stripe_event: stripe_event}}) do
    :ok = handle_webhook(event_type, stripe_event)

    Logger.info("handled #{event_type} #{stripe_event.type}")
  catch
    kind, value ->
      message =
        "unhandled error in webhook:\n#{inspect(%{kind: kind, value: value, event_type: event_type, event: stripe_event})}"

      Sentry.capture_message(message, stacktrace: __STACKTRACE__)
      Logger.error(message)
  end

  defp success_response(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end

  defp handle_webhook(:connect, %{
         type: "checkout.session.completed",
         data: %{object: %{client_reference_id: "order_number_" <> _} = session}
       }) do
    {:ok, _} =
      session
      |> Orders.handle_session()
      |> OrderNotifier.deliver_order_confirmation_emails(TodoplaceWeb.Helpers)

    :ok
  end

  defp handle_webhook(:connect, %{
         type: "checkout.session.completed",
         data: %{object: %{client_reference_id: "proposal_" <> _} = session}
       }) do
    {:ok, _} = PaymentSchedules.handle_payment(session, TodoplaceWeb.Helpers)
    :ok
  end

  defp handle_webhook(
         :connect,
         %{
           type: "payment_intent.canceled",
           data: %{object: payment_intent}
         } = object
       ) do
    {:ok, _} =
      payment_intent
      |> Orders.handle_intent()
      |> OrderNotifier.deliver_order_cancelation_emails(TodoplaceWeb.Helpers)

    message = "Payment intent is cancelled, #{inspect(object)}"
    Sentry.capture_message(message)
    Logger.info(message)

    :ok
  end

  defp handle_webhook(:app, %{
         type: "customer.subscription.trial_will_end",
         data: %{object: subscription}
       }) do
    {:ok, _} = Todoplace.Subscriptions.handle_trial_ending_soon(subscription)
    :ok
  end

  defp handle_webhook(:app, %{type: type, data: %{object: subscription}})
       when type in [
              "customer.subscription.created",
              "customer.subscription.updated",
              "customer.subscription.deleted"
            ] do
    {:ok, _} = Todoplace.Subscriptions.handle_stripe_subscription(subscription)
    :ok
  end

  defp handle_webhook(:app, %{type: type, data: %{object: %Stripe.Invoice{subscription: "" <> _}}})
       when type in [
              "invoice.payment_succeeded",
              "invoice.payment_failed"
            ] do
    Logger.debug("ignored subscription #{type} webhook")
    :ok
  end

  defp handle_webhook(:app, %{type: type, data: %{object: invoice}})
       when type in [
              "invoice.payment_succeeded",
              "invoice.payment_failed"
            ] do
    {:ok, _} = Orders.handle_invoice(invoice)
    :ok
  end

  defp handle_webhook(:app, %{type: "customer.source.expiring", data: %{object: card}}) do
    if card.customer do
      Accounts.get_user_by_stripe_customer_id(card.customer.id)
    end

    :ok
  end
end
