defmodule Todoplace.Repo.Migrations.CreateUserOrganizations do
  use Ecto.Migration

  def change do
    execute("CREATE TYPE role AS ENUM ('admin', 'member')")

    create table(:users_organizations, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :role, :role, null: false
      add :status, :string

      timestamps()
    end

    create unique_index(:users_organizations, [:user_id, :organization_id])
  end
end
