defmodule Todoplace.Repo.Migrations.AddOnboardingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:onboarding, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})
    end
  end
end
