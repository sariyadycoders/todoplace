defmodule Todoplace.Repo.Migrations.AddIsProofingToAlbum do
  use Ecto.Migration

  def change do
    alter table(:albums) do
      add(:is_proofing, :boolean, null: false, default: false)
    end
  end
end
