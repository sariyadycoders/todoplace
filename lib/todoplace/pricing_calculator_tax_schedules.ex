defmodule Todoplace.PricingCalculatorTaxSchedules do
  @moduledoc false

  import Ecto.Changeset

  use Ecto.Schema

  defmodule IncomeBracket do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field(:income_min, Money.Ecto.Amount.Type)
      field(:income_max, Money.Ecto.Amount.Type)
      field(:percentage, :decimal)
      field(:fixed_cost_start, Money.Ecto.Amount.Type)
      field(:fixed_cost, Money.Ecto.Amount.Type)
    end
  end

  schema "pricing_calculator_tax_schedules" do
    field(:year, :integer)
    field(:self_employment_percentage, :decimal)
    field(:active, :boolean)
    embeds_many(:income_brackets, IncomeBracket)

    timestamps(type: :utc_datetime)
  end

  def changeset(
        %Todoplace.PricingCalculatorTaxSchedules{} = pricing_calculator_tax_schedules,
        attrs \\ %{}
      ) do
    pricing_calculator_tax_schedules
    |> cast(attrs, [:year, :active, :self_employment_percentage])
    |> cast_embed(:income_brackets, with: &income_bracket_changeset(&1, &2))
  end

  defp income_bracket_changeset(income_bracket, attrs) do
    income_bracket
    |> cast(attrs, [:income_min, :income_max, :percentage, :fixed_cost_start, :fixed_cost])
  end

  def add_income_bracket_changeset(tax_schedule, attrs) do
    income_brackets = tax_schedule.income_brackets

    tax_schedule
    |> change()
    |> put_embed(:income_brackets, [attrs | income_brackets])
  end
end
