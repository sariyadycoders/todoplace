defmodule Todoplace.Repo.Migrations.AddUuidToPhotosTable do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add(:uuid, :string)
    end
  end
end
