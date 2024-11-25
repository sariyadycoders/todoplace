defmodule Todoplace.Repo.Migrations.AddOrganizationIdToNotifications do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      # Add organization_id as a foreign key
      add :organization_id, references(:organizations, on_delete: :nothing)
    end

    # Optional: Index for faster lookups
    create index(:notifications, [:organization_id])
  end
end
