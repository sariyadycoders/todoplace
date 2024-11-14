defmodule Todoplace.Repo.Migrations.AddAspectToPhoto do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add(:aspect_ratio, :float)
    end
  end
end
