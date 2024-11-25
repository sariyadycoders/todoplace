defmodule Todoplace.Repo.Migrations.AddEnumFoOrganizationStatus do
  use Ecto.Migration

  def up do
    execute "CREATE TYPE organization_status AS ENUM ('active', 'inactive', 'deleted')"

    alter table(:users_organizations) do
      add :org_status, :organization_status, null: false, default: "active"
    end
  end

  def down do
    alter table(:users_organizations) do
      remove :org_status
    end

    execute "DROP TYPE organization_status"
  end
end
