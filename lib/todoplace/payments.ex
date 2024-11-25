defmodule Todoplace.Payments do
  alias Todoplace.{
    Accounts.User,
    Organization,
    Repo
  }

  require Logger

  @tax_codes %{
    digital: "txcd_10501000",
    product: "txcd_99999999",
    services: "txcd_20030000",
    shipping: "txcd_92010001"
  }

  @payment_options %{
    allow_affirm: "affirm",
    allow_afterpay_clearpay: "afterpay_clearpay",
    allow_klarna: "klarna",
    allow_cashapp: "cashapp"
  }

  @moduledoc "behavior of (stripe) payout processor"

  @type product_data() :: %{
          :name => String.t(),
          optional(:description) => String.t(),
          optional(:images) => [String.t()],
          optional(:metadata) => Stripe.Types.metadata()
        }

  @type price_data() :: %{
          :currency => String.t(),
          optional(:product_data) => product_data(),
          optional(:unit_amount) => integer()
        }

  @type line_item() :: %{
          optional(:name) => String.t(),
          optional(:quantity) => integer(),
          optional(:amount) => integer(),
          optional(:currency) => String.t(),
          optional(:description) => String.t(),
          optional(:dynamic_tax_rates) => [String.t()],
          optional(:images) => [String.t()],
          optional(:price) => String.t(),
          optional(:price_data) => price_data(),
          optional(:tax_rates) => [String.t()]
        }

  @type create_customer() :: %{
          optional(:email) => String.t(),
          optional(:name) => String.t()
        }

  @type create_account_link() :: %{
          :account => Stripe.Account.t() | Stripe.id(),
          :refresh_url => String.t(),
          :return_url => String.t(),
          :type => String.t(),
          optional(:collect) => String.t()
        }

  @type create_account() :: %{
          :type => String.t(),
          optional(:country) => String.t(),
          optional(:account_token) => String.t(),
          optional(:business_type) => String.t(),
          optional(:email) => String.t(),
          optional(:external_account) => String.t(),
          optional(:metadata) => Stripe.Types.metadata()
        }

  @type create_subscription() :: %{
          :customer => Stripe.id() | Stripe.Customer.t(),
          :items => [
            %{
              optional(:price) => Stripe.id() | Stripe.Price.t(),
              optional(:quantity) => non_neg_integer()
            }
          ],
          optional(:trial_period_days) => non_neg_integer()
        }

  @type create_subscription_schedule() :: %{
          :customer => Stripe.id() | Stripe.Customer.t(),
          :phases => [
            %{
              :items => [
                %{
                  optional(:price) => Stripe.id() | Stripe.Price.t(),
                  optional(:quantity) => non_neg_integer()
                }
              ],
              :iterations => non_neg_integer(),
              optional(:trial_period_days) => non_neg_integer()
            }
          ]
        }

  @callback create_customer(create_customer(), Stripe.options()) ::
              {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}

  @callback update_customer(String.t(), map(), Stripe.options()) ::
              {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}

  @callback retrieve_customer(String.t(), keyword(binary())) ::
              {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}

  @callback construct_event(String.t(), String.t(), String.t()) ::
              {:ok, Stripe.Event.t()} | {:error, any}

  @callback create_session(Stripe.Session.create_params(), Stripe.options()) ::
              {:ok, Stripe.Session.t()} | {:error, any}

  @callback retrieve_session(String.t(), keyword(binary())) ::
              {:ok, Stripe.Session.t()} | {:error, Stripe.Error.t()}

  @callback expire_session(String.t(), keyword(binary())) ::
              {:ok, Stripe.Session.t()} | {:error, Stripe.Error.t()}

  @callback retrieve_account(binary(), Stripe.options()) ::
              {:ok, Stripe.Account.t()} | {:error, Stripe.Error.t()}

  @callback create_account(create_account(), Stripe.options()) ::
              {:ok, Stripe.Account.t()} | {:error, Stripe.Error.t()}

  @callback create_subscription_schedule(create_subscription_schedule(), Stripe.options()) ::
              {:ok, Stripe.Subscription.t()} | {:error, Stripe.Error.t()}

  @callback create_subscription(create_subscription(), Stripe.options()) ::
              {:ok, Stripe.Subscription.t()} | {:error, Stripe.Error.t()}

  @callback update_subscription(Stripe.id() | String.t(), params, Stripe.options()) ::
              {:ok, Stripe.Subscription.t()} | {:error, Stripe.Error.t()}
            when params: %{:coupon => String.t()} | %{}

  @callback retrieve_subscription(String.t(), keyword(binary())) ::
              {:ok, Stripe.Subscription.t()} | {:error, Stripe.Error.t()}

  @callback list_prices(%{optional(:active) => boolean()}) ::
              {:ok, Stripe.List.t(Stripe.Price.t())} | {:error, Stripe.Error.t()}

  @callback list_promotion_codes(%{optional(:active) => boolean()}) ::
              {:ok, Stripe.List.t(Stripe.PromotionCode.t())} | {:error, Stripe.Error.t()}

  @callback create_billing_portal_session(%{customer: String.t()}) ::
              {:ok, Stripe.BillingPortal.Session.t()} | {:error, Stripe.Error.t()}

  @callback setup_intent(params, Stripe.options()) ::
              {:ok, Stripe.SetupIntent.t()} | {:error, Stripe.Error.t()}
            when params:
                   %{
                     optional(:confirm) => boolean(),
                     optional(:customer) => Stripe.id() | Stripe.Customer.t(),
                     optional(:description) => String.t(),
                     optional(:metadata) => map(),
                     optional(:on_behalf_of) => Stripe.id() | Stripe.Account.t(),
                     optional(:payment_method) => Stripe.id(),
                     optional(:payment_method_options) => map(),
                     optional(:payment_method_types) => [String.t()],
                     optional(:return_url) => String.t(),
                     optional(:usage) => String.t()
                   }
                   | %{}

  @callback retrieve_payment_intent(binary(), Stripe.options()) ::
              {:ok, Stripe.PaymentIntent.t()} | {:error, Stripe.Error.t()}

  @callback capture_payment_intent(binary(), Stripe.options()) ::
              {:ok, Stripe.PaymentIntent.t()} | {:error, Stripe.Error.t()}

  @callback cancel_payment_intent(binary(), Stripe.options()) ::
              {:ok, Stripe.PaymentIntent.t()} | {:error, Stripe.Error.t()}

  @callback create_account_link(create_account_link(), Stripe.options()) ::
              {:ok, Stripe.AccountLink.t()} | {:error, Stripe.Error.t()}

  @callback create_invoice(params, Stripe.options()) ::
              {:ok, Stripe.Invoice.t()} | {:error, Stripe.Error.t()}
            when params:
                   %{
                     optional(:application_fee_amount) => integer(),
                     optional(:auto_advance) => boolean(),
                     optional(:collection_method) => String.t(),
                     :customer => Stripe.id() | Stripe.Customer.t(),
                     optional(:custom_fields) => Stripe.Invoice.custom_fields(),
                     optional(:days_until_due) => integer(),
                     optional(:default_payment_method) => String.t(),
                     optional(:default_source) => String.t(),
                     optional(:default_tax_rates) => [Stripe.id()],
                     optional(:description) => String.t(),
                     optional(:due_date) => Stripe.timestamp(),
                     optional(:footer) => String.t(),
                     optional(:metadata) => Stripe.Types.metadata(),
                     optional(:statement_descriptor) => String.t(),
                     optional(:subscription) => Stripe.id() | Stripe.Subscription.t(),
                     optional(:tax_percent) => number()
                   }
                   | %{}

  @callback finalize_invoice(Stripe.id() | Stripe.Invoice.t(), params, Stripe.options()) ::
              {:ok, Stripe.Invoice.t()} | {:error, Stripe.Error.t()}
            when params: %{:id => String.t(), optional(:auto_advance) => boolean()} | %{}

  @callback void_invoice(Stripe.id() | Stripe.Invoice.t(), Stripe.options()) ::
              {:ok, Stripe.Invoice.t()} | {:error, Stripe.Error.t()}

  @callback create_invoice_item(params, Stripe.options()) ::
              {:ok, Stripe.Invoiceitem.t()} | {:error, Stripe.Error.t()}
            when params:
                   %{
                     optional(:amount) => integer(),
                     :currency => String.t(),
                     :customer => Stripe.id() | Stripe.Customer.t(),
                     optional(:description) => String.t(),
                     optional(:discountable) => boolean(),
                     optional(:invoice) => Stripe.id() | Stripe.Invoice.t(),
                     optional(:metadata) => Stripe.Types.metadata(),
                     optional(:price) => Stripe.id() | Stripe.Price.t(),
                     optional(:quantity) => integer(),
                     optional(:subscription) => Stripe.id() | Stripe.Subscription.t(),
                     optional(:tax_rates) => [String.t()],
                     optional(:unit_amount) => integer(),
                     optional(:unit_amount_decimal) => String.t()
                   }
                   | %{}

  def create_session(params, opts) do
    params =
      Enum.into(params, %{
        payment_method_types: [
          "card"
        ],
        mode: "payment",
        automatic_tax: %{enabled: true}
      })

    Logger.info("Reached Payments.create_session for #{inspect(params)}")

    case impl().create_session(params, opts) do
      {:ok, _} = session -> session
      _error -> params |> Map.drop([:automatic_tax]) |> impl().create_session(opts)
    end
  end

  def retrieve_session(id, opts), do: impl().retrieve_session(id, opts)
  def expire_session(id, opts), do: impl().expire_session(id, opts)
  def create_customer(params, opts), do: impl().create_customer(params, opts)

  def update_customer(customer_id, params, opts),
    do: impl().update_customer(customer_id, params, opts)

  def retrieve_customer(id, opts \\ []), do: impl().retrieve_customer(id, opts)
  def retrieve_account(id, opts \\ []), do: impl().retrieve_account(id, opts)
  def create_subscription(params, opts \\ []), do: impl().create_subscription(params, opts)

  def create_subscription_schedule(params, opts \\ []),
    do: impl().create_subscription_schedule(params, opts)

  def update_subscription(id, params, opts \\ []),
    do: impl().update_subscription(id, params, opts)

  def retrieve_subscription(id, opts), do: impl().retrieve_subscription(id, opts)
  def list_prices(params), do: impl().list_prices(params)
  def list_promotion_codes(params), do: impl().list_promotion_codes(params)
  def create_account_link(params), do: impl().create_account_link(params, [])
  def create_account(params, opts \\ []), do: impl().create_account(params, opts)
  def create_billing_portal_session(params), do: impl().create_billing_portal_session(params)
  def setup_intent(params, opts \\ []), do: impl().setup_intent(params, opts)
  def retrieve_payment_intent(id, opts), do: impl().retrieve_payment_intent(id, opts)
  def capture_payment_intent(id, opts), do: impl().capture_payment_intent(id, opts)
  def cancel_payment_intent(id, opts), do: impl().cancel_payment_intent(id, opts)
  def create_invoice(params, opts \\ []), do: impl().create_invoice(params, opts)
  def finalize_invoice(id, params, opts \\ []), do: impl().finalize_invoice(id, params, opts)
  def void_invoice(id, opts \\ []), do: impl().void_invoice(id, opts)
  def create_invoice_item(params, opts \\ []), do: impl().create_invoice_item(params, opts)

  def construct_event(body, signature, secret),
    do: impl().construct_event(body, signature, secret)

  @spec status(Organization.t() | User.t()) ::
          {:ok, :none | :processing | :charges_enabled | :details_submitted}
  def status(%User{} = user) do
    %{organization: organization} = user |> Repo.preload(:organization)
    status(organization)
  end

  def status(%Organization{stripe_account_id: nil}), do: :no_account

  def status(%Organization{stripe_account_id: account_id}) do
    Todoplace.StripeStatusCache.current_for(account_id, fn ->
      case retrieve_account(account_id) do
        {:ok, account} ->
          account_status(account)

        {:error, error} ->
          Logger.error(error)
          :error
      end
    end)
  end

  def simple_status(%User{} = user) do
    %{organization: organization} = user |> Repo.preload(:organization)
    simple_status(organization)
  end

  def simple_status(%Organization{stripe_account_id: nil}), do: :no_account

  def simple_status(%Organization{stripe_account_id: _}), do: :charges_enabled

  def account_status(%Stripe.Account{charges_enabled: true}), do: :charges_enabled

  def account_status(%Stripe.Account{
        requirements: %{disabled_reason: "requirements.pending_verification"}
      }),
      do: :pending_verification

  def account_status(%Stripe.Account{}), do: :missing_information

  def custom_link(%User{} = user, opts) do
    %{organization: organization} = user |> Repo.preload(:organization)
    custom_link(organization, opts)
  end

  def custom_link(%Organization{stripe_account_id: nil} = organization, opts) do
    with {:ok, %{id: account_id}} <- create_account(%{type: "standard"}),
         {:ok, organization} <-
           organization
           |> Organization.assign_stripe_account_changeset(account_id)
           |> Repo.update() do
      custom_link(organization, opts)
    else
      {:error, _} = e -> e
      e -> {:error, e}
    end
  end

  def custom_link(%Organization{stripe_account_id: account_id}, opts) do
    refresh_url = opts |> Keyword.get(:refresh_url)
    return_url = opts |> Keyword.get(:return_url)

    case create_account_link(%{
           account: account_id,
           refresh_url: refresh_url,
           return_url: return_url,
           type: "account_onboarding"
         }) do
      {:ok, %{url: url}} -> {:ok, url}
      error -> error
    end
  end

  def tax_code(key), do: Map.get(@tax_codes, key)

  def map_payment_opts_to_stripe_opts(%{payment_options: payment_options} = _organization) do
    options =
      payment_options
      |> Map.from_struct()
      |> Map.delete(:allow_cash)
      |> Enum.reduce([], fn {key, value}, acc ->
        if value do
          [payment_option(key) | acc]
        else
          acc
        end
      end)

    # always allow card payments
    options ++ ["card"]
  end

  def check_and_map_offline(
        options,
        %{payment_options: %{allow_cash: allow_cash}} = _organization
      ) do
    if allow_cash do
      options ++ ["cash"]
    else
      options
    end
  end

  def payment_option(key), do: Map.get(@payment_options, key)

  defp impl, do: Application.get_env(:todoplace, :payments)
end
