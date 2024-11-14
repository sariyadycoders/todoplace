defmodule Todoplace.Repo.Migrations.AddNotCollectShippingToPackage do
  use Ecto.Migration

  def up do
    alter table(:packages) do
      add(:not_collect_shipping_tax, :boolean, default: false)
    end
  end

  def down do
    alter table(:packages) do
      remove(:not_collect_shipping_tax)
    end
  end
end
