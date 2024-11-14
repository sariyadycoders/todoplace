defmodule Todoplace.Repo.Migrations.AddPricing do
  use Ecto.Migration

  def change do
    create table(:pricing_calculations) do
      add(:organization_id, references(:organizations, on_delete: :nothing))
      add(:average_time_per_week, :integer)
      add(:average_days_per_week, {:array, :string})
      add(:desired_salary, :integer)
      add(:tax_bracket, :decimal)
      add(:after_income_tax, :integer)
      add(:self_employment_tax_percentage, :decimal)
      add(:take_home, :integer)
      add(:job_types, {:array, :string})
      add(:schedule, :string)
      add(:min_years_experience, :integer)
      add(:zipcode, :string)

      add(:state, references(:cost_of_living_adjustments, column: :state, type: :string),
        null: false
      )

      add(:business_costs, :map, default: fragment("'[]'::jsonb"))
      add(:pricing_suggestions, :map, default: fragment("'[]'::jsonb"))

      timestamps()
    end

    create table(:pricing_calculator_tax_schedules) do
      add(:year, :integer)
      add(:self_employment_percentage, :decimal)
      add(:active, :boolean)
      add(:income_brackets, :map, default: fragment("'[]'::jsonb"))

      timestamps()
    end

    create table(:pricing_calculator_business_costs) do
      add(:category, :string)
      add(:description, :string)
      add(:active, :boolean)
      add(:line_items, :map, default: fragment("'[]'::jsonb"))

      timestamps()
    end

    alter table("package_base_prices") do
      add(:max_session_per_year, :integer)
    end
  end
end
