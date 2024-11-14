defmodule Todoplace.Package do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias Todoplace.{Repo, Shoot, Accounts.User, PackagePaymentSchedule}
  require Ecto.Query
  import Ecto.Query

  schema "packages" do
    field :archived_at, :utc_datetime
    field :base_multiplier, :decimal, default: 1
    field :base_price, Money.Ecto.Map.Type
    field :description, :string
    field :thumbnail_url, :string
    field :download_count, :integer
    field :download_each_price, Money.Ecto.Map.Type
    field :job_type, :string
    field :name, :string
    field :shoot_count, :integer
    field :print_credits, Money.Ecto.Map.Type
    field :collected_price, Money.Ecto.Map.Type
    field :buy_all, Money.Ecto.Map.Type
    field :turnaround_weeks, :integer, default: 1
    field :schedule_type, :string
    field :fixed, :boolean, default: true
    field :show_on_public_profile, :boolean, default: false
    field :print_credits_include_in_total, :boolean, default: false
    field :digitals_include_in_total, :boolean, default: false
    field :discount_base_price, :boolean, default: false
    field :discount_digitals, :boolean, default: false
    field :discount_print_credits, :boolean, default: false
    field :is_template, :boolean, default: false

    belongs_to :questionnaire_template, Todoplace.Questionnaire
    belongs_to(:organization, Todoplace.Organization)
    belongs_to(:package_template, __MODULE__, on_replace: :nilify)

    belongs_to(:package_currency, Todoplace.Currency,
      references: :code,
      type: :string,
      foreign_key: :currency
    )

    has_one(:job, Todoplace.Job)
    has_one(:contract, Todoplace.Contract)

    has_many(:package_payment_schedules, PackagePaymentSchedule,
      where: [package_payment_preset_id: nil]
    )

    timestamps()
  end

  def changeset(package \\ %__MODULE__{}, attrs, opts) do
    steps = [
      choose_template: &choose_template/3,
      details: &create_details/3,
      pricing: &update_pricing/3
    ]

    step = Keyword.get(opts, :step, :pricing)

    Enum.reduce_while(steps, package, fn {step_name, initializer}, changeset ->
      {if(step_name == step, do: :halt, else: :cont), initializer.(changeset, attrs, opts)}
    end)
  end

  @fields ~w[base_price currency organization_id name download_count download_each_price base_multiplier print_credits buy_all shoot_count turnaround_weeks is_template]a
  def changeset_for_create_gallery(package \\ %__MODULE__{}, attrs) do
    package
    |> cast(attrs, @fields)
    |> validate_required(~w[download_count name download_each_price organization_id shoot_count]a)
    |> validate_number(:download_count, greater_than_or_equal_to: 0)
    |> then(fn changeset ->
      if Map.get(attrs, "status") !== :unlimited do
        changeset
        |> validate_money(:download_each_price,
          greater_than: 200,
          message: "must be greater than two"
        )
      else
        changeset
      end
    end)
    |> validate_money(:print_credits,
      greater_than_or_equal_to: 0,
      message: "must be equal to or less than total price"
    )
  end

  def import_changeset(package \\ %__MODULE__{}, attrs) do
    changeset = package |> cast(attrs, [:base_price, :currency])
    currency = get_field(changeset, :currency)

    base_price = get_field(changeset, :base_price) || Money.new(0, currency)
    skip_base_price = Money.zero?(base_price)

    package
    |> create_details(attrs, skip_description: true)
    |> update_pricing(attrs, skip_base_price: skip_base_price)
    |> cast(attrs, ~w[collected_price currency]a)
    |> then(fn changeset ->
      changeset
      |> put_change(
        :collected_price,
        get_field(changeset, :collected_price) || Money.new(0, currency)
      )
      |> validate_money(:collected_price,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: base_price.amount
      )
    end)
  end

  def create_from_template_changeset(package \\ %__MODULE__{}, attrs) do
    package
    |> choose_template(attrs)
    |> validate_required([:package_template_id])
    |> create_details(attrs)
    |> update_pricing(attrs)
  end

  def archive_changeset(package),
    do: change(package, %{archived_at: DateTime.truncate(DateTime.utc_now(), :second)})

  def edit_visibility_changeset(package),
    do: change(package, %{show_on_public_profile: !package.show_on_public_profile})

  defp choose_template(package, attrs, _opts \\ []) do
    package |> cast(attrs, [:package_template_id])
  end

  defp create_details(package, attrs, opts \\ []) do
    package
    |> cast(
      attrs,
      ~w[discount_base_price discount_digitals discount_print_credits digitals_include_in_total print_credits_include_in_total schedule_type fixed description thumbnail_url questionnaire_template_id name organization_id shoot_count print_credits turnaround_weeks show_on_public_profile job_type is_template]a
    )
    |> validate_required(~w[name organization_id shoot_count turnaround_weeks job_type]a)
    |> validate_number(:shoot_count, less_than_or_equal_to: 10)
    |> validate_number(:turnaround_weeks,
      greater_than_or_equal_to: 1,
      message: "must be greater or equal to 1"
    )
    |> then(fn changeset ->
      if Keyword.get(opts, :skip_description) do
        changeset
      else
        changeset |> validate_required(~w[description]a)
      end
    end)
    |> then(fn changeset ->
      if Keyword.get(opts, :validate_shoot_count) do
        package_id = Ecto.Changeset.get_field(changeset, :id)

        changeset
        |> validate_number(:shoot_count,
          greater_than_or_equal_to: shoot_count_minimum(package_id)
        )
      else
        changeset
      end
    end)
  end

  def update_pricing(package, attrs, opts \\ []) do
    package
    |> cast(
      attrs,
      ~w[discount_base_price discount_digitals discount_print_credits digitals_include_in_total print_credits_include_in_total schedule_type fixed base_price download_count download_each_price base_multiplier print_credits buy_all currency is_template]a
    )
    |> validate_required(~w[base_price download_count download_each_price currency]a)
    |> then(fn changeset ->
      currency = get_field(changeset, :currency) || Todoplace.Currency.default_currency()
      fallback_price = Money.new(0, currency)

      if Keyword.get(opts, :skip_base_price) do
        changeset
        |> put_change(:base_price, fallback_price)
        |> put_change(:print_credits, fallback_price)
      else
        changeset
        |> validate_required(~w[base_price]a)
        |> put_change(
          :print_credits,
          get_field(changeset, :print_credits) || fallback_price
        )
      end
    end)
    |> validate_number(:download_count, greater_than_or_equal_to: 0)
    |> then(fn changeset ->
      status = Map.get(attrs, "status")

      if status && status !== :unlimited do
        changeset
        |> validate_money(:download_each_price,
          greater_than: 200,
          message: "must be greater than two"
        )
      else
        changeset
      end
    end)
    |> then(fn changeset ->
      currency = get_field(changeset, :currency)
      base_price = get_field(changeset, :base_price) || Money.new(0, currency)

      changeset
      |> validate_money(:print_credits,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: base_price.amount,
        message: "must be equal to or less than total price"
      )
    end)
    |> validate_money(:buy_all)
  end

  def digitals_price(%__MODULE__{} = package),
    do: Money.multiply(download_each_price(package), download_count(package))

  def download_each_price(%__MODULE__{download_each_price: nil, currency: currency}),
    do: Money.new(0, currency)

  def download_each_price(%__MODULE__{download_each_price: %{amount: amount}, currency: currency}),
    do: Money.new(amount, currency)

  def download_count(%__MODULE__{download_count: nil}), do: 0
  def download_count(%__MODULE__{download_count: download_count}), do: download_count

  def base_price(%__MODULE__{base_price: nil, currency: currency}), do: Money.new(0, currency)

  def base_price(%__MODULE__{base_price: %{amount: amount}, currency: currency}),
    do: Money.new(amount, currency)

  def print_credits(%__MODULE__{print_credits: nil, currency: currency}),
    do: Money.new(0, currency)

  def print_credits(%__MODULE__{print_credits: %{amount: amount}, currency: currency}),
    do: Money.new(amount, currency)

  # apply base multiplier to base price
  def adjusted_base_price(
        %__MODULE__{base_multiplier: multiplier, discount_base_price: true} = package
      ),
      do: package |> base_price() |> Money.multiply(multiplier)

  # by default base price is not discounted
  def adjusted_base_price(%__MODULE__{base_multiplier: _, discount_base_price: false} = package),
    do: package |> base_price()

  def base_adjustment(%__MODULE__{} = package),
    do: package |> adjusted_base_price() |> Money.subtract(base_price(package))

  def adjusted_print_cridets(%__MODULE__{base_multiplier: multiplier} = package),
    do: package |> print_credits() |> Money.multiply(multiplier)

  def print_cridets_adjustment(%__MODULE__{} = package),
    do: package |> adjusted_print_cridets() |> Money.subtract(print_credits(package))

  def adjusted_digitals_price(%__MODULE__{base_multiplier: multiplier} = package),
    do: digitals_price(package) |> Money.multiply(multiplier)

  def digitals_adjustment(%__MODULE__{} = package),
    do: package |> adjusted_digitals_price() |> Money.subtract(digitals_price(package))

  def price(%__MODULE__{currency: currency} = package) do
    print_credits_price =
      if package.print_credits_include_in_total do
        print_credits(package)
      else
        Money.new(0, currency)
      end

    digitals_price =
      if package.digitals_include_in_total do
        Money.add(print_credits_price, digitals_price(package))
      else
        print_credits_price
      end

    updated_price =
      if package.discount_base_price || !Money.zero?(base_adjustment(package)) do
        Money.add(base_price(package), base_adjustment(package))
      else
        base_price(package)
      end

    updated_price =
      if package.discount_print_credits do
        Money.add(updated_price, print_cridets_adjustment(package))
      else
        updated_price
      end

    update_price =
      if package.discount_digitals do
        Money.add(updated_price, digitals_adjustment(package))
      else
        updated_price
      end

    Money.add(digitals_price, update_price)
  end

  def price_before_discounts(%__MODULE__{currency: currency} = package) do
    print_credits_price =
      if package.print_credits_include_in_total do
        print_credits(package)
      else
        Money.new(0, currency)
      end

    digitals_price =
      if package.digitals_include_in_total do
        Money.add(print_credits_price, digitals_price(package))
      else
        print_credits_price
      end

    base_price = base_price(package)

    Money.add(digitals_price, base_price)
  end

  def templates_for_organization(organization_id) do
    templates_for_organization_query(organization_id)
    |> where([package], package.show_on_public_profile)
  end

  def templates_for_organization_query(organization_id) do
    from(package in __MODULE__,
      where:
        package.is_template and package.organization_id == ^organization_id and
          is_nil(package.archived_at),
      order_by: [desc: package.base_price]
    )
  end

  def archived_templates_for_organization(organization_id) do
    from(package in __MODULE__,
      where:
        not is_nil(package.job_type) and package.organization_id == ^organization_id and
          not is_nil(package.archived_at),
      order_by: [desc: package.base_price]
    )
  end

  def templates_for_user(%User{organization_id: organization_id}, type) when type != nil do
    from(template in templates_for_organization_query(organization_id),
      where: template.job_type == ^type
    )
  end

  def validate_money(changeset, fields, validate_number_opts \\ [greater_than_or_equal_to: 0])

  def validate_money(changeset, [_ | _] = fields, validate_number_opts) do
    for field <- fields, reduce: changeset do
      changeset ->
        validate_money(changeset, field, validate_number_opts)
    end
  end

  def validate_money(changeset, field, validate_number_opts) do
    validate_change(changeset, field, fn
      field, %Money{amount: amount} ->
        {%{field => nil}, %{field => :integer}}
        |> change(%{field => amount})
        |> validate_number(
          field,
          Keyword.put_new(validate_number_opts, :less_than_or_equal_to, 142_857_000)
        )
        |> Map.get(:errors)
        |> Keyword.take([field])
    end)
  end

  defp shoot_count_minimum(package_id) do
    Shoot
    |> join(:inner, [shoot], job in assoc(shoot, :job), on: job.package_id == ^package_id)
    |> Repo.aggregate(:count)
  end

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          description: String.t(),
          thumbnail_url: String.t(),
          organization_id: integer(),
          shoot_count: integer(),
          turnaround_weeks: integer(),
          schedule_type: String.t(),
          fixed: boolean(),
          print_credits_include_in_total: boolean(),
          discount_print_credits: boolean(),
          discount_digitals: boolean(),
          discount_base_price: boolean(),
          digitals_include_in_total: boolean(),
          base_price: Money.t(),
          download_count: integer(),
          download_each_price: Money.t(),
          base_multiplier: float(),
          print_credits: Money.t(),
          buy_all: Money.t(),
          job_type: String.t(),
          show_on_public_profile: boolean(),
          archived_at: DateTime.t(),
          is_template: boolean()
        }
end
