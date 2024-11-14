defmodule Todoplace.Subscriptions do
  @moduledoc false
  alias Todoplace.{
    Repo,
    SubscriptionPlan,
    SubscriptionEvent,
    SubscriptionPromotionCode,
    Payments,
    Subscription,
    Accounts.User,
    SubscriptionPlansMetadata,
    Organization
  }

  import Todoplace.Zapier.User, only: [user_subscription_ending_soon_webhook: 1]
  import TodoplaceWeb.Helpers, only: [days_distance: 1]
  import TodoplaceWeb.LiveHelpers, only: [to_integer: 1]
  import Ecto.Query
  require Logger

  def sync_subscription_plans() do
    {:ok, %{data: prices}} = Payments.list_prices(%{active: true})

    for price <- Enum.filter(prices, &(&1.type == "recurring")) do
      %{
        stripe_price_id: price.id,
        price: price.unit_amount,
        recurring_interval: price.recurring.interval,
        # setting active to false to avoid conflicting prices on sync
        active: false
      }
      |> SubscriptionPlan.changeset()
      |> Repo.insert!(
        conflict_target: [:stripe_price_id],
        on_conflict: {:replace, [:price, :recurring_interval, :updated_at]}
      )
    end
  end

  def sync_trialing_subscriptions() do
    {:ok, %{data: subscriptions}} = Stripe.Subscription.list(%{status: "trialing"})

    for subscription <- subscriptions do
      {:ok, customer} = Stripe.Customer.retrieve(subscription |> Map.get(:customer))
      user = Repo.get_by(User, email: customer.email)

      if user && User.onboarded?(user) && !user.stripe_customer_id do
        user
        |> User.assign_stripe_customer_changeset(customer.id)
        |> Repo.update!()

        {:ok, _} = handle_stripe_subscription(subscription)
      end
    end
  end

  def sync_subscription_promotion_codes() do
    case Payments.list_promotion_codes(%{active: true, limit: 100}) do
      {:ok, %{data: promotion_codes}} ->
        for %{
              code: code,
              coupon: %{
                id: id,
                percent_off: percent_off,
                amount_off: amount_off,
                currency: currency
              }
            } <-
              promotion_codes do
          %{
            stripe_promotion_code_id: id,
            code: code,
            percent_off: percent_off,
            amount_off: amount_off,
            currency: currency
          }
          |> SubscriptionPromotionCode.changeset()
          |> Repo.insert!(
            conflict_target: [:stripe_promotion_code_id],
            on_conflict: {:replace, [:code, :updated_at]}
          )
        end

        {:ok, "Sync from stripe succeeded"}

      {:error, _} ->
        {:error, "Sync from stripe failed"}
    end
  end

  def subscription_ending_soon_info(nil), do: %{hidden?: true, hidden_for_days?: true}

  def subscription_ending_soon_info(%User{subscription: %Ecto.Association.NotLoaded{}} = user),
    do: user |> Repo.preload(:subscription) |> subscription_ending_soon_info()

  def subscription_ending_soon_info(%User{subscription: subscription}) do
    case subscription do
      %{current_period_end: current_period_end, cancel_at: cancel_at} when cancel_at != nil ->
        days_left = days_distance(current_period_end)
        setting = Todoplace.AdminGlobalSettings.get_settings_by_slug("free_trial")

        %{
          hidden?: calculate_days_left_boolean(days_left, 7),
          hidden_for_days?: calculate_days_left_boolean(days_left, to_integer(setting.value)),
          days_left: days_left |> Kernel.max(0),
          subscription_end_at: DateTime.to_date(current_period_end)
        }

      _ ->
        %{hidden?: true, hidden_for_days?: true}
    end
  end

  def next_payment?(%Subscription{} = subscription),
    do: subscription.active && !subscription.cancel_at

  def interval(%Subscription{recurring_interval: recurring_interval}), do: recurring_interval
  def interval(_), do: nil

  def subscription_expired?(%User{subscription: %Ecto.Association.NotLoaded{}} = user),
    do: user |> Repo.preload(:subscription) |> subscription_expired?()

  def subscription_expired?(%User{subscription: subscription}),
    do: subscription && !subscription.active

  def subscription_payment_method?(%User{stripe_customer_id: stripe_customer_id}) do
    case stripe_customer_id do
      nil -> false
      _ -> Payments.retrieve_customer(stripe_customer_id) |> check_card_source()
    end
  end

  def subscription_payment_method?(_), do: false

  def subscription_plans() do
    Repo.all(from(s in SubscriptionPlan, where: s.active == true, order_by: s.price))
  end

  def all_subscription_plans() do
    Repo.all(from(s in SubscriptionPlan, order_by: s.price))
  end

  def organizations_with_active_subscription() do
    from(o in Organization,
      join: u in assoc(o, :user),
      join: s in assoc(u, :subscription),
      where: s.status in ["active", "trialing"]
    )
    |> Repo.all()
  end

  def maybe_return_promotion_code_id?(code) do
    case maybe_get_promotion_code?(code) do
      %{stripe_promotion_code_id: stripe_promotion_code_id} ->
        stripe_promotion_code_id

      _ ->
        nil
    end
  end

  def maybe_get_promotion_code?(%{onboarding: %{promotion_code: promotion_code}}) do
    maybe_get_promotion_code?(promotion_code)
  end

  def maybe_get_promotion_code?(nil), do: nil

  def maybe_get_promotion_code?(code) do
    case Repo.get_by(SubscriptionPromotionCode, %{code: code}) do
      %{stripe_promotion_code_id: _} = code ->
        code

      _ ->
        nil
    end
  end

  def get_subscription_plan(recurring_interval \\ "month"),
    do: Repo.get_by!(SubscriptionPlan, %{recurring_interval: recurring_interval, active: true})

  def subscription_base(%User{} = user, recurring_interval, opts) do
    subscription_plan = get_subscription_plan(recurring_interval)

    trial_days = opts |> Keyword.get(:trial_days)

    promotion_code =
      case maybe_get_promotion_code?(user) do
        %{stripe_promotion_code_id: stripe_promotion_code_id} ->
          stripe_promotion_code_id

        _ ->
          nil
      end

    stripe_params = %{
      customer: user_customer_id(user),
      items: [
        %{
          quantity: 1,
          price: subscription_plan.stripe_price_id
        }
      ],
      coupon: promotion_code,
      payment_settings: %{
        save_default_payment_method: "on_subscription"
      },
      trial_settings: %{
        end_behavior: %{
          missing_payment_method: "cancel"
        }
      },
      trial_period_days: trial_days
    }

    case Payments.create_subscription(stripe_params) do
      {:ok, subscription} -> subscription
      err -> err
    end
  end

  def checkout_link(%User{} = user, recurring_interval, opts) do
    subscription_plan = get_subscription_plan(recurring_interval)

    cancel_url = opts |> Keyword.get(:cancel_url)
    success_url = opts |> Keyword.get(:success_url)
    trial_days = opts |> Keyword.get(:trial_days)
    promotion_code = opts |> Keyword.get(:promotion_code)

    subscription_data =
      if trial_days, do: %{subscription_data: %{trial_period_days: trial_days}}, else: %{}

    discounts_data =
      if promotion_code,
        do: %{
          discounts: [
            %{
              coupon: promotion_code
            }
          ]
        },
        else: %{}

    stripe_params =
      %{
        cancel_url: cancel_url,
        success_url: success_url,
        customer: user_customer_id(user),
        billing_address_collection: "auto",
        mode: "subscription",
        line_items: [
          %{
            quantity: 1,
            price: subscription_plan.stripe_price_id
          }
        ]
      }
      |> Map.merge(subscription_data)
      |> Map.merge(discounts_data)

    case Payments.create_session(stripe_params, opts) do
      {:ok, %{url: url}} -> {:ok, url}
      err -> err
    end
  end

  def handle_stripe_subscription(%Stripe.Subscription{} = subscription) do
    with %SubscriptionPlan{id: subscription_plan_id} <-
           Repo.get_by(SubscriptionPlan, stripe_price_id: subscription.plan.id),
         %User{id: user_id} <-
           Repo.get_by(User, stripe_customer_id: subscription.customer) do
      %{
        user_id: user_id,
        subscription_plan_id: subscription_plan_id,
        status: subscription.status,
        stripe_subscription_id: subscription.id,
        cancel_at: subscription.cancel_at |> to_datetime,
        current_period_start: subscription.current_period_start |> to_datetime,
        current_period_end: subscription.current_period_end |> to_datetime
      }
      |> SubscriptionEvent.changeset()
      |> Repo.insert()
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end

  def handle_subscription_by_session_id(session_id) do
    with {:ok, session} <-
           Payments.retrieve_session(session_id, []),
         {:ok, subscription} <-
           Payments.retrieve_subscription(session.subscription, []),
         {:ok, _} <- handle_stripe_subscription(subscription) do
      :ok
    else
      e ->
        Logger.warning("no match when retrieving stripe session: #{inspect(e)}")
        e
    end
  end

  def handle_trial_ending_soon(%Stripe.Subscription{customer: customer_id}) do
    %{email: email} = Todoplace.Accounts.get_user_by_stripe_customer_id(customer_id)

    user_subscription_ending_soon_webhook(%{email: email})
  end

  def billing_portal_link(%User{stripe_customer_id: customer_id}, return_url) do
    case Payments.create_billing_portal_session(%{customer: customer_id, return_url: return_url}) do
      {:ok, session} -> {:ok, session.url}
      error -> error
    end
  end

  def ensure_active_subscription!(%User{} = user) do
    if Todoplace.Subscriptions.subscription_expired?(user) do
      raise Ecto.NoResultsError, queryable: Organization
    end
  end

  def user_customer_id(%User{stripe_customer_id: nil} = user, attrs) do
    params = %{name: user.name, email: user.email} |> Map.merge(attrs)

    with {:ok, %{id: customer_id}} <- Payments.create_customer(params, []),
         {:ok, user} <-
           user
           |> User.assign_stripe_customer_changeset(customer_id)
           |> Repo.update() do
      user.stripe_customer_id
    else
      {:error, _} = e -> e
      e -> {:error, e}
    end
  end

  def user_customer_id(%User{stripe_customer_id: customer_id}, _attrs), do: customer_id

  def user_customer_id(%User{stripe_customer_id: nil} = user) do
    params = %{name: user.name, email: user.email}

    with {:ok, %{id: customer_id}} <- Payments.create_customer(params, []),
         {:ok, user} <-
           user
           |> User.assign_stripe_customer_changeset(customer_id)
           |> Repo.update() do
      user.stripe_customer_id
    else
      {:error, _} = e -> e
      e -> {:error, e}
    end
  end

  def user_customer_id(%User{stripe_customer_id: customer_id}), do: customer_id

  def all_subscription_plans_metadata(), do: Repo.all(from(s in SubscriptionPlansMetadata))

  def get_subscription_plan_metadata(code), do: subscription_plan_metadata(code)
  def get_subscription_plan_metadata(), do: subscription_plan_metadata()

  defp subscription_plan_metadata(%Todoplace.SubscriptionPlansMetadata{} = query), do: query

  defp subscription_plan_metadata(nil),
    do: subscription_plan_metadata_default()

  defp subscription_plan_metadata(code),
    do:
      Repo.get_by(SubscriptionPlansMetadata, code: code, active: true)
      |> subscription_plan_metadata()

  defp subscription_plan_metadata(),
    do: subscription_plan_metadata_default()

  defp subscription_plan_metadata_default() do
    setting = Todoplace.AdminGlobalSettings.get_settings_by_slug("free_trial")
    days = to_integer(setting.value)

    %Todoplace.SubscriptionPlansMetadata{
      trial_length: days,
      onboarding_description:
        "Your #{days}-day free trial lets you explore and use all of our amazing features. To get started we’ll ask you to enter your credit card to keep your account secure and for us to focus the team on those who are really interested in Todoplace.",
      onboarding_title: "Start your #{days}-day free trial",
      signup_description: "Start your free trial",
      signup_title: "Get started with your #{days}-day free trial today",
      success_title: "Your #{days}-day free trial has started!"
    }
  end

  defp to_datetime(nil), do: nil
  defp to_datetime(unix_date), do: DateTime.from_unix!(unix_date)

  defp check_card_source(
         {:ok,
          %Stripe.Customer{invoice_settings: %{default_payment_method: default_payment_method}}}
       ) do
    case default_payment_method do
      nil -> false
      _ -> true
    end
  end

  defp check_card_source({:error, _}), do: false

  defp calculate_days_left_boolean(days_left, max) do
    days_left > max || days_left < 0
  end
end
