defmodule Todoplace.Repo.Migrations.AddCollectSessionTaxToPackage do
  use Ecto.Migration

  def up do
    alter table(:packages) do
      add(:not_collect_session_tax, :boolean, default: false)
    end
  end

  def down do
    alter table(:packages) do
      remove(:not_collect_session_tax)
    end
  end
end
