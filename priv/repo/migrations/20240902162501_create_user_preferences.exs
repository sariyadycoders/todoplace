defmodule Todoplace.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :settings, :map, default: %{}  # Using a JSON field for flexible settings storage

      timestamps()
    end

    create unique_index(:user_preferences, [:user_id])
  end
end
