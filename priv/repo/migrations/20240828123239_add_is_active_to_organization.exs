defmodule Todoplace.Repo.Migrations.AddIsActiveToOrganization do
  use Ecto.Migration

    def up do
      alter table(:organizations) do
        add :is_active, :boolean, null: false, default: true
      end
    end

    def down do
      alter table(:organizations) do
        remove(:is_active)
      end
    end
end
