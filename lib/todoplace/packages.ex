defmodule Todoplace.Packages do
  @moduledoc "context module for packages"

  alias Ecto.Multi

  alias Todoplace.{
    Accounts.User,
    Organization,
    Profiles,
    Package,
    Repo,
    Job,
    JobType,
    BookingEvent,
    Packages.BasePrice,
    Packages.CostOfLivingAdjustment,
    PackagePaymentSchedule,
    Questionnaire,
    PackagePayments,
    Contract,
    Contracts,
    BookingEvent
  }

  import Todoplace.Repo.CustomMacros
  import Todoplace.Package, only: [validate_money: 3]
  import Ecto.Query, only: [from: 2]

  @payment_defaults_fixed %{
    "wedding" => ["To Book", "6 Months Before", "Week Before"],
    "family" => ["To Book", "Day Before Shoot"],
    "maternity" => ["To Book", "Day Before Shoot"],
    "newborn" => ["To Book", "Day Before Shoot"],
    "event" => ["To Book", "Day Before Shoot"],
    "headshot" => ["To Book"],
    "portrait" => ["To Book"],
    "mini" => ["To Book"],
    "boudoir" => ["To Book", "Day Before Shoot"],
    "global" => ["To Book", "Day Before Shoot"],
    "payment_due_book" => ["To Book"],
    "splits_2" => ["To Book", "Day Before Shoot"],
    "splits_3" => ["To Book", "6 Months Before", "Week Before"]
  }

  defmodule PackagePricing do
    @moduledoc "For setting buy_all and print_credits price"
    use Ecto.Schema
    import Ecto.Changeset
    alias Todoplace.Packages.Download

    @primary_key false
    embedded_schema do
      field(:is_enabled, :boolean)
      field(:print_credits_include_in_total, :boolean)
    end

    def changeset(package_pricing \\ %__MODULE__{}, attrs) do
      package_pricing
      |> cast(attrs, [:is_enabled, :print_credits_include_in_total])
      |> then(
        &if(get_field(&1, :is_enabled),
          do: &1,
          else: force_change(&1, :print_credits_include_in_total, false)
        )
      )
    end

    def handle_package_params(package, params) do
      currency = Map.get(package, "currency")

      case Map.get(params, "package_pricing", %{})
           |> Map.get("is_enabled") do
        "false" ->
          Map.put(package, "print_credits", Download.zero_price(currency))
          |> Map.put("print_credits_include_in_total", false)

        _ ->
          package
      end
    end
  end

  defmodule Multiplier do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    import TodoplaceWeb.PackageLive.Shared, only: [current: 1]

    @sign_options [{"Discount", "-"}, {"Surcharge", "+"}]

    @primary_key false
    embedded_schema do
      field(:percent, :float, default: 0.0)
      field(:sign, :string, default: @sign_options |> hd |> elem(1))
      field(:is_enabled, :boolean)
      field(:discount_base_price, :boolean, default: false)
      field(:discount_print_credits, :boolean, default: false)
      field(:discount_digitals, :boolean, default: false)
    end

    def changeset(
          multiplier \\ %__MODULE__{},
          attrs,
          print_credits_include_in_total,
          digitals_include_in_total
        ) do
      multiplier
      |> cast(attrs, [
        :percent,
        :sign,
        :is_enabled,
        :discount_base_price,
        :discount_print_credits,
        :discount_digitals
      ])
      |> validate_required([:percent, :sign, :is_enabled])
      |> then(
        &if(get_field(&1, :is_enabled) && Map.get(attrs, "step") in [:choose_type, :pricing],
          do:
            force_change(
              &1,
              :discount_print_credits,
              print_credits_include_in_total && get_field(&1, :discount_print_credits)
            )
            |> force_change(
              :discount_digitals,
              digitals_include_in_total && get_field(&1, :discount_digitals)
            )
            |> validate_discounts(),
          else:
            &1
            |> force_change(:discount_base_price, false)
            |> force_change(:discount_print_credits, false)
            |> force_change(:discount_digitals, false)
        )
      )
    end

    defp validate_discounts(changeset) do
      if current(changeset) |> is_discounts_enabled() do
        changeset
      else
        changeset
        |> validate_acceptance(:discount_base_price, message: "Field must be selected")
      end
    end

    def is_discounts_enabled(multiplier) do
      Map.get(multiplier, :discount_base_price) ||
        Map.get(multiplier, :discount_print_credits) ||
        Map.get(multiplier, :discount_digitals)
    end

    def sign_options(), do: @sign_options

    def from_decimal(%{base_multiplier: d} = package) do
      case d |> Decimal.sub(1) |> Decimal.mult(100) |> Decimal.to_float() do
        0.0 ->
          %__MODULE__{is_enabled: false}

        percent when percent < 0 ->
          %__MODULE__{percent: abs(percent), sign: "-", is_enabled: true}

        percent when percent > 0 ->
          %__MODULE__{percent: percent, sign: "+", is_enabled: true}
      end
      |> Map.merge(%{
        discount_base_price: Map.get(package, :discount_base_price, false),
        discount_print_credits: Map.get(package, :discount_print_credits, false),
        discount_digitals: Map.get(package, :discount_digitals, false)
      })
    end

    def to_decimal(%__MODULE__{is_enabled: false}), do: Decimal.new(1)

    def to_decimal(%__MODULE__{sign: sign, percent: percent}) do
      case sign do
        "+" -> percent_to_decimal(percent)
        "-" -> percent |> percent_to_decimal() |> Decimal.negate()
      end
      |> Decimal.div(100)
      |> Decimal.add(1)
    end

    defp percent_to_decimal(value) do
      if is_float(value) do
        Decimal.from_float(value)
      else
        Decimal.new(value)
      end
    end
  end

  defmodule Download do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset
    import TodoplaceWeb.PackageLive.Shared, only: [current: 1]

    alias Todoplace.Package

    @default_each_price_amount 5000

    @primary_key false
    embedded_schema do
      field(:status, Ecto.Enum, values: [:limited, :unlimited, :none])
      field(:is_custom_price, :boolean, default: false)
      field(:includes_credits, :boolean, default: false)
      field(:digitals_include_in_total, :boolean, default: false)
      field(:each_price, Money.Ecto.Map.Type)
      field(:count, :integer)
      field(:currency, :string)
      field(:buy_all, Money.Ecto.Map.Type)
      field(:is_buy_all, :boolean)
    end

    def changeset(download \\ %__MODULE__{}, attrs, status_changeset \\ nil) do
      changeset =
        download
        |> cast(attrs, [
          :status,
          :is_custom_price,
          :includes_credits,
          :each_price,
          :count,
          :is_buy_all,
          :buy_all,
          :digitals_include_in_total,
          :currency
        ])

      currency = get_field(changeset, :currency)
      zero_price = zero_price(currency)

      if Map.get(attrs, "step") in [:choose_type, :pricing, :package_payment] do
        changeset
        |> validate_required([:status])
        |> then(
          &if get_field(&1, :status) == :unlimited,
            do:
              Enum.reduce(
                [
                  each_price: zero_price,
                  is_custom_price: false,
                  includes_credits: false,
                  is_buy_all: false,
                  buy_all: nil,
                  digitals_include_in_total: false
                ],
                &1,
                fn {k, v}, changeset -> force_change(changeset, k, v) end
              ),
            else: &1
        )
        |> then(
          &if(get_field(&1, :status) == :none,
            do:
              &1
              |> force_change(:digitals_include_in_total, false)
              |> validate_required([:each_price])
              |> validate_inclusion(:is_custom_price, ["true"]),
            else: &1
          )
        )
        |> then(
          &if(get_field(&1, :status) == :limited,
            do:
              &1
              |> force_change(:count, get_field(&1, :count))
              |> validate_required([:count])
              |> validate_inclusion(:is_custom_price, ["true"])
              |> validate_number(:count, greater_than: 0),
            else: force_change(&1, :count, nil)
          )
        )
        |> then(
          &if(get_field(&1, :status) != :unlimited,
            do: update_buy_all(&1, download, status_changeset),
            else: &1
          )
        )
        |> validate_buy_all(zero_price)
        |> validate_each_price(zero_price)
      else
        changeset
      end
    end

    defp update_buy_all(changeset, download, status_changeset) do
      each_price = get_field(changeset, :each_price)
      buy_all = get_field(changeset, :buy_all)
      is_buy_all = get_field(changeset, :is_buy_all) || (is_nil(buy_all) && download.buy_all)
      updated_buy_all = if is_nil(buy_all), do: download.buy_all, else: buy_all

      updated_each_price =
        with true <- get_status(status_changeset) == :unlimited,
             true <- each_price && Money.zero?(each_price) do
          download.each_price
        else
          _ -> each_price
        end

      changeset
      |> force_change(:each_price, updated_each_price)
      |> force_change(:buy_all, updated_buy_all)
      |> force_change(:is_buy_all, is_buy_all)
      |> Package.validate_money(:each_price,
        greater_than: 200,
        message: "must be greater than two"
      )
    end

    defp get_status(status_changeset),
      do: if(status_changeset, do: current(status_changeset) |> Map.get(:status), else: nil)

    defp validate_buy_all(changeset, zero_price) do
      download_each_price = get_field(changeset, :each_price) || zero_price

      if get_field(changeset, :is_buy_all) do
        changeset
        |> validate_required([:buy_all])
      else
        changeset
      end
      |> validate_money(:buy_all,
        greater_than: download_each_price.amount,
        message: "Must be greater than digital image price"
      )
    end

    defp validate_each_price(changeset, zero_price) do
      buy_all = get_field(changeset, :buy_all) || zero_price

      if Money.zero?(buy_all) do
        changeset
      else
        changeset
        |> validate_money(:each_price,
          less_than: buy_all.amount,
          message: "Must be less than buy all price"
        )
      end
    end

    def from_package(package, global_settings \\ %{download_each_price: nil, buy_all_price: nil})

    def from_package(package, nil),
      do: from_package(package, %{download_each_price: nil, buy_all_price: nil})

    # called when creating new package
    def from_package(
          %{download_each_price: nil, buy_all: nil, download_count: nil, currency: currency} =
            package,
          global_settings
        ),
        do:
          Map.merge(
            %__MODULE__{
              status: :none,
              is_custom_price: true,
              is_buy_all: true,
              currency: currency
            },
            set_download_fields(package, global_settings)
          )

    # Called when editing existing package
    def from_package(
          %{download_each_price: each_price, download_count: count, id: id, currency: currency} =
            package,
          global_settings
        )
        when not is_nil(id) do
      cond do
        count > 0 ->
          %__MODULE__{
            status: :limited,
            is_custom_price: true,
            count: count,
            digitals_include_in_total: Map.get(package, :digitals_include_in_total, false),
            currency: currency
          }
          |> Map.merge(
            set_each_price(%{each_price: each_price, currency: currency}, global_settings)
          )
          |> Map.merge(set_buy_all(package, global_settings))

        each_price && Money.positive?(each_price) ->
          %__MODULE__{
            status: :none,
            is_custom_price: true,
            count: nil,
            currency: currency
          }
          |> Map.merge(
            set_each_price(%{each_price: each_price, currency: currency}, global_settings)
          )
          |> Map.merge(set_buy_all(package, global_settings))

        true ->
          %__MODULE__{status: :unlimited, is_custom_price: true, count: nil, currency: currency}
          |> Map.merge(set_default_download_each_price(global_settings, currency))
          |> Map.merge(set_buy_all(package, global_settings))
      end
    end

    def from_package(
          %{download_count: count, currency: currency} = package,
          global_settings
        )
        when count > 0 do
      Map.merge(
        %__MODULE__{
          status: :limited,
          is_custom_price: true,
          is_buy_all: true,
          digitals_include_in_total: Map.get(package, :digitals_include_in_total, false),
          currency: currency
        },
        set_download_fields(package, global_settings)
      )
      |> set_count_fields(count)
    end

    def from_package(
          %{download_each_price: each_price, currency: currency} = package,
          global_settings
        )
        when not is_nil(each_price) and each_price.amount > 0 do
      Map.merge(
        %__MODULE__{status: :none, is_custom_price: true, is_buy_all: true, currency: currency},
        set_download_fields(package, global_settings)
      )
    end

    def from_package(%{download_count: count, currency: currency}, _),
      do:
        set_count_fields(
          %__MODULE__{
            status: :unlimited,
            is_custom_price: false,
            each_price: zero_price(currency),
            buy_all: nil,
            is_buy_all: false,
            currency: currency
          },
          count
        )

    def count(%__MODULE__{count: nil}), do: 0
    def count(%__MODULE__{count: count}), do: count

    def each_price(download, currency \\ "USD")
    def each_price(%__MODULE__{status: :unlimited}, currency), do: zero_price(currency)

    def each_price(%__MODULE__{each_price: %{amount: amount}}, currency),
      do: Money.new(amount, currency)

    def each_price(_, _), do: nil

    def buy_all(%__MODULE__{is_buy_all: false}), do: nil
    def buy_all(%__MODULE__{buy_all: buy_all}), do: buy_all

    def default_each_price_amount(), do: @default_each_price_amount
    def zero_price(currency), do: Money.new(0, currency)

    defp set_download_fields(%{currency: currency} = package, global_settings) do
      if is_nil(package.id) do
        set_default_download_each_price(global_settings, currency)
      else
        set_each_price(package, global_settings)
      end
      |> Map.merge(set_buy_all(package, global_settings))
    end

    defp set_each_price(%{each_price: each_price, currency: currency}, global_settings) do
      if each_price && !Money.zero?(each_price),
        do: %{each_price: each_price},
        else: set_default_download_each_price(global_settings, currency)
    end

    defp set_default_download_each_price(global_settings, currency) do
      each_price = global_settings.download_each_price
      amount = if(each_price, do: each_price.amount, else: @default_each_price_amount)

      %{each_price: Money.new(amount, currency)}
    end

    defp set_buy_all(%{buy_all: buy_all, currency: currency}, %{
           buy_all_price: buy_all_price = global_settings
         }) do
      buy_all_price = buy_all_price && Money.new(buy_all_price.amount, currency)

      cond do
        buy_all && Money.zero?(buy_all) && global_settings.buy_all_price ->
          %{buy_all: buy_all_price, is_buy_all: true}

        buy_all ->
          %{buy_all: Money.new(buy_all.amount, currency), is_buy_all: true}

        true ->
          %{buy_all: buy_all_price, is_buy_all: false}
      end
    end

    defp set_count_fields(download, count) when count in [nil, 0],
      do: %{download | count: count, includes_credits: false}

    defp set_count_fields(download, count),
      do: %{download | count: count, includes_credits: true}
  end

  def get_payment_defaults(), do: @payment_defaults_fixed

  def get_payment_defaults(schedule_type) do
    Map.get(@payment_defaults_fixed, schedule_type, ["To Book", "6 Months Before", "Week Before"])
  end

  def future_date, do: ~U[3022-01-01 00:00:00Z]

  def templates_with_single_shoot(%User{organization_id: organization_id}) do
    query = Package.templates_for_organization_query(organization_id)

    from(package in query, where: package.shoot_count == 1)
    |> Repo.all()
  end

  def templates_for_user(user, job_type),
    do: user |> Package.templates_for_user(job_type) |> Repo.all()

  def templates_for_organization(%Organization{id: id}),
    do: id |> Package.templates_for_organization_query() |> Repo.all()

  def insert_package_and_update_booking_event(changeset, booking_event, opts \\ %{}) do
    Multi.new()
    |> Multi.insert(:package, changeset)
    |> Multi.update(:booking_event_update, fn changes ->
      BookingEvent.update_package_template(booking_event, %{
        package_template_id: changes.package.id
      })
    end)
    |> maybe_update_questionnaire_package_id_multi(changeset, opts)
    |> merge_multi(opts)
  end

  def insert_package_and_update_job(changeset, job, opts \\ %{}) do
    Multi.new()
    |> Multi.insert(:package, changeset)
    |> maybe_update_questionnaire_package_id_multi(changeset, opts)
    |> Multi.update(:job_update, fn changes ->
      Job.add_package_changeset(job, %{package_id: changes.package.id})
    end)
    |> Multi.merge(fn _ ->
      payment_schedules = Map.get(opts, :payment_schedules)

      shoot_date =
        if payment_schedules && Enum.any?(payment_schedules),
          do: payment_schedules |> List.first() |> Map.get(:shoot_date),
          else: false

      if Map.get(opts, :action) == :insert && shoot_date do
        PackagePayments.insert_job_payment_schedules(Map.put(opts, :job_id, job.id))
      else
        Multi.new()
      end
    end)
    |> merge_multi(opts)
  end

  def build_package_changeset(
        %{
          current_user: current_user,
          step: step,
          is_template: is_template,
          package: package,
          job: job
        },
        params
      ) do
    params = Map.put(params, "organization_id", current_user.organization_id)

    package
    |> Map.put(:package_payment_schedules, [])
    |> Package.changeset(params,
      step: step,
      is_template: is_template,
      validate_shoot_count: job && package.id
    )
  end

  def build_package_changeset(
        %{
          current_user: current_user,
          step: step,
          is_template: is_template,
          package: package,
          booking_event: booking_event
        },
        params
      ) do
    params = Map.put(params, "organization_id", current_user.organization_id)

    package
    |> Map.put(:package_payment_schedules, [])
    |> Package.changeset(params,
      step: step,
      is_template: is_template,
      validate_shoot_count: booking_event && package.id
    )
  end

  def insert_or_update_package(changeset, contract_params, opts) do
    action = Map.get(opts, :action)
    shoot_date = opts.payment_schedules |> List.first() |> Map.get(:shoot_date)

    result =
      Multi.new()
      |> Multi.insert_or_update(:package, changeset)
      |> Multi.merge(fn %{package: %{id: id}} ->
        if action in [:insert, :insert_preset, :update, :update_preset] do
          PackagePayments.delete_schedules(id, Map.get(opts, :payment_preset))
        else
          Multi.new()
        end
      end)
      |> Multi.merge(fn _ ->
        if action == :update && shoot_date do
          PackagePayments.delete_job_payment_schedules(Map.get(opts, :job_id))
        else
          Multi.new()
        end
      end)
      |> Multi.merge(fn %{package: package} ->
        if action in [:insert, :insert_preset, :update, :update_preset] do
          PackagePayments.insert_schedules(package, opts)
        else
          Multi.new()
        end
      end)
      |> Multi.merge(fn _ ->
        if action == :update && shoot_date do
          PackagePayments.insert_job_payment_schedules(opts)
        else
          Multi.new()
        end
      end)
      |> Multi.merge(fn %{package: package} ->
        contract_multi(package, contract_params)
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{package: package}} -> {:ok, package}
      _ -> {:error}
    end
  end

  defp merge_multi(multi, opts) do
    multi
    |> Multi.merge(fn %{package: package} ->
      if Map.get(opts, :action) in [:insert, :insert_preset] do
        PackagePayments.insert_schedules(package, opts)
      else
        Multi.new()
      end
    end)
    |> Multi.merge(fn %{package: package} ->
      case package |> Repo.preload(package_template: :contract) do
        %{package_template: %{contract: %Contract{} = contract}} ->
          contract_params = %{
            "name" => contract.name,
            "content" => contract.content,
            "contract_template_id" => contract.contract_template_id
          }

          Contracts.insert_contract_multi(package, contract_params)

        package ->
          if Map.get(opts, :contract_params) do
            Contracts.insert_contract_multi(package, opts.contract_params)
          else
            Multi.new()
          end
      end
    end)
  end

  defp contract_multi(package, contract_params) do
    cond do
      is_nil(contract_params) ->
        Multi.new()

      Map.get(contract_params, "edited") ->
        Contracts.insert_template_and_contract_multi(package, contract_params)

      !Map.get(contract_params, "edited") ->
        Contracts.insert_contract_multi(package, contract_params)
    end
  end

  def changeset_from_template(%Package{id: template_id} = template) do
    template
    |> Map.from_struct()
    |> Map.merge(%{package_template_id: template_id, is_template: false})
    |> Package.create_from_template_changeset()
  end

  defdelegate job_types(), to: JobType, as: :all

  defdelegate job_name(job), to: Job, as: :name

  defdelegate price(price), to: Package

  def discount_percent(package),
    do:
      (case(Multiplier.from_decimal(package)) do
         %{sign: "-", is_enabled: true, percent: percent} -> percent
         _ -> nil
       end)

  def create_initial(
        %User{
          onboarding: %{photographer_years: years_experience, schedule: schedule, state: state}
        } = user
      )
      when is_integer(years_experience) and is_atom(schedule) and is_binary(state) do
    %{organization: %{organization_job_types: job_types}} =
      user = Repo.preload(user, organization: :organization_job_types)

    enabled_job_types = Profiles.enabled_job_types(job_types)

    create_templates(user, enabled_job_types)
  end

  def create_initial(_user), do: []

  def create_initial(
        %User{
          onboarding: %{photographer_years: years_experience, schedule: schedule, state: state}
        } = user,
        job_type
      )
      when is_integer(years_experience) and is_atom(schedule) and is_binary(state) do
    create_templates(user, job_type)
  end

  def create_initial(_user, _type), do: []

  def get_price(
        %{base_multiplier: base_multiplier, base_price: base_price},
        presets_count,
        index
      ) do
    base_price = if(base_price, do: base_price, else: 0)

    amount =
      Decimal.mult(base_price, base_multiplier)
      |> Decimal.round(0, :floor)
      |> Decimal.to_integer()

    total_price = div(amount, 100)

    remainder = rem(total_price, presets_count)
    amount = if remainder == 0, do: total_price, else: total_price - remainder

    if index + 1 == presets_count do
      amount / presets_count + remainder
    else
      amount / presets_count
    end
    |> Kernel.trunc()
  end

  def make_package_payment_schedule(templates) do
    templates
    |> Enum.map(&get_package_payment_schedule/1)
    |> List.flatten()
  end

  defp create_templates(user, job_types) do
    job_types = if is_list(job_types), do: job_types, else: List.wrap(job_types)

    templates_params =
      from(q in templates_query(user), where: q.job_type in ^job_types)
      |> Repo.all()
      |> Enum.map(fn template ->
        template
        |> Map.put_new(:is_template, true)
        |> Map.replace(:inserted_at, NaiveDateTime.truncate(template.inserted_at, :second))
        |> Map.replace(:updated_at, NaiveDateTime.truncate(template.updated_at, :second))
      end)

    Multi.new()
    |> Multi.insert_all(:templates, Package, templates_params, returning: true)
    |> Multi.insert_all(:package_payment_schedules, PackagePaymentSchedule, fn %{
                                                                                 templates:
                                                                                   {_, templates}
                                                                               } ->
      make_package_payment_schedule(templates)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{templates: {_, templates}}} -> templates
      {:error, _} -> []
    end
  end

  # TODO: To delete this later
  # defp delete_contract_questionnaire_package(x_booking_event, opts) do
  #   PackagePayments.delete_schedules(
  #     x_booking_event.package_template_id,
  #     Map.get(opts, :payment_preset)
  #   )
  #   |> Multi.merge(fn _ ->
  #     case Repo.get_by(Questionnaire, package_id: x_booking_event.package_template_id) do
  #       nil ->
  #         Multi.new()

  #       questionnaire ->
  #         Multi.new()
  #         |> Multi.delete(:delete_questionnaire, questionnaire)
  #     end
  #   end)
  #   |> Multi.merge(fn _ ->
  #     case Repo.get_by(Contract, package_id: x_booking_event.package_template_id) do
  #       nil ->
  #         Multi.new()

  #       contract ->
  #         Multi.new()
  #         |> Multi.delete(:delete_contract, contract)
  #     end
  #   end)
  #   |> Multi.delete(
  #     :delete_package,
  #     Repo.get!(Package, x_booking_event.package_template_id)
  #   )
  # end

  defp get_package_payment_schedule(package) do
    current_date = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    default_presets = get_payment_defaults(package.job_type)
    count = length(default_presets)

    base_price = %{
      base_multiplier: package.base_multiplier,
      base_price: package.base_price.amount
    }

    Enum.with_index(
      default_presets,
      fn default, index ->
        %{
          package_id: package.id,
          price: Money.new(get_price(base_price, count, index) * 100),
          description: "$#{get_price(base_price, count, index)} #{default}",
          schedule_date: future_date(),
          interval: true,
          due_interval: default,
          inserted_at: current_date,
          updated_at: current_date
        }
      end
    )
  end

  defp minimum_years_query(years_experience),
    do:
      from(base in BasePrice,
        select: max(base.min_years_experience),
        where: base.min_years_experience <= ^years_experience
      )

  defp templates_query(%User{
         onboarding: %{photographer_years: years_experience, schedule: schedule, state: state},
         organization_id: organization_id
       }) do
    full_time = schedule == :full_time
    nearest = 500
    zero_price = Download.zero_price("USD")
    default_each_price = Money.new(Download.default_each_price_amount(), "USD")

    from(base in BasePrice,
      where:
        base.full_time == ^full_time and
          base.min_years_experience in subquery(minimum_years_query(years_experience)),
      inner_lateral_join:
        name in ([base.tier, base.job_type] |> array_to_string(" ") |> initcap()),
      on: true,
      join: adjustment in CostOfLivingAdjustment,
      on: adjustment.state == ^state,
      select: %{
        base_price:
          type(
            fragment(
              "jsonb_build_object('amount', (?::numeric)::integer, 'currency', (?::text))",
              nearest(
                fragment(
                  "(?::numeric * (?->>'amount')::numeric)::numeric",
                  adjustment.multiplier,
                  base.base_price
                ),
                ^nearest
              ),
              "USD"
            ),
            base.base_price
          ),
        description: coalesce(base.description, name.initcap),
        download_count: base.download_count,
        download_each_price: type(^default_each_price, base.base_price),
        inserted_at: now(),
        job_type: base.job_type,
        buy_all: base.buy_all,
        schedule_type: base.job_type,
        fixed: type(^true, base.full_time),
        print_credits: type(^zero_price, base.print_credits),
        name: name.initcap,
        organization_id: type(^organization_id, base.id),
        shoot_count: base.shoot_count,
        turnaround_weeks: base.turnaround_weeks,
        updated_at: now()
      }
    )
  end

  defp maybe_update_questionnaire_package_id_multi(
         multi,
         %{changes: %{organization_id: organization_id}},
         %{questionnaire: questionnaire}
       ) do
    multi
    |> Multi.insert(
      :questionnaire,
      fn %{package: %{id: package_id}} ->
        Questionnaire.clean_questionnaire_for_changeset(
          questionnaire,
          organization_id,
          package_id
        )
      end
    )
    |> Multi.update(:package_update, fn %{
                                          package: package,
                                          questionnaire: %{id: questionnaire_id}
                                        } ->
      package
      |> Package.changeset(%{questionnaire_template_id: questionnaire_id}, step: nil)
    end)
  end

  defp maybe_update_questionnaire_package_id_multi(multi, _, _), do: multi

  def get_current_user(user_id) do
    from(user in Todoplace.Accounts.User,
      where: user.id == ^user_id,
      join: org in assoc(user, :organization),
      left_join: subscription in assoc(user, :subscription),
      preload: [:subscription, [organization: :organization_job_types]]
    )
    |> Repo.one()
  end

  def archive_packages_for_job_type(job_type, organization_id) do
    from(p in Package,
      where: p.organization_id == ^organization_id and p.job_type == ^job_type
    )
    |> Repo.update_all(
      set: [
        archived_at: DateTime.truncate(DateTime.utc_now(), :second),
        show_on_public_profile: false
      ]
    )
  end

  def unarchive_packages_for_job_type(job_type, organization_id) do
    from(p in Package,
      where: p.organization_id == ^organization_id and p.job_type == ^job_type
    )
    |> Repo.update_all(set: [archived_at: nil, show_on_public_profile: false])
  end

  def packages_exist?(job_type, organization_id) do
    from(p in Package,
      where: p.organization_id == ^organization_id and p.job_type == ^job_type
    )
    |> Repo.exists?()
  end

  def paginate_query(query, %{limit: limit, offset: offset}) do
    from query,
      limit: ^limit,
      offset: ^offset
  end

  def update_all_query(package_ids, opts) do
    from(p in Package, where: p.id in ^package_ids, update: [set: ^opts])
  end

  def get_recent_packages(user) do
    query = Package.templates_for_organization_query(user.organization_id)

    from(q in query, order_by: [desc: q.inserted_at], limit: 6) |> Repo.all()
  end
end
