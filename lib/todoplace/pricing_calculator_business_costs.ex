defmodule Todoplace.PricingCalculatorBusinessCosts do
  @moduledoc false

  import Ecto.Changeset

  use Ecto.Schema

  defmodule BusinessCost do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field(:yearly_cost, Money.Ecto.Amount.Type)
      field(:title, :string)
      field(:description, :string)
    end
  end

  schema "pricing_calculator_business_costs" do
    field(:category, :string)
    field(:active, :boolean)
    field(:description, :string)
    embeds_many(:line_items, BusinessCost)

    timestamps(type: :utc_datetime)
  end

  def changeset(
        %Todoplace.PricingCalculatorBusinessCosts{} = pricing_calculator_business_costs,
        attrs \\ %{}
      ) do
    pricing_calculator_business_costs
    |> cast(attrs, [:category, :active, :description])
    |> cast_embed(:line_items, with: &business_cost_changeset(&1, &2))
  end

  defp business_cost_changeset(business_cost, attrs) do
    business_cost
    |> cast(attrs, [:yearly_cost, :title, :description])
  end

  def add_business_cost_changeset(business_cost, attrs) do
    line_items = business_cost.line_items

    business_cost
    |> change()
    |> put_embed(:line_items, [attrs | line_items])
  end
end
