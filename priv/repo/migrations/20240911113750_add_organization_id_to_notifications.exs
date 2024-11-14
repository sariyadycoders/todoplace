defmodule Todoplace.Repo.Migrations.AddOrganizationIdToNotifications do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add :organization_id, references(:organizations, on_delete: :nothing)  # Add organization_id as a foreign key
    end

    create index(:notifications, [:organization_id])  # Optional: Index for faster lookups
  end
end
