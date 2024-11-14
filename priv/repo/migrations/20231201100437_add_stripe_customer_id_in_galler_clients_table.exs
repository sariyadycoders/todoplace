defmodule Todoplace.Repo.Migrations.AddStripeCustomerIdInGallerClientsTable do
  use Ecto.Migration

  def change do
    alter table(:gallery_clients) do
      add(:stripe_customer_id, :string)
    end
  end
end
