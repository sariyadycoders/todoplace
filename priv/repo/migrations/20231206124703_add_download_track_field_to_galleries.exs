defmodule Todoplace.Repo.Migrations.AddDownloadTrackFieldToGalleries do
  use Ecto.Migration

  def change do
    alter table(:galleries) do
      add(:download_tracking, {:array, :map})
    end
  end
end
