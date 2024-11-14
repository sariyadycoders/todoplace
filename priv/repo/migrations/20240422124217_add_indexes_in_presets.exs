defmodule Todoplace.Repo.Migrations.AddIndexesInPresets do
  use Ecto.Migration

  def up do
    create(index(:email_presets, [:type]))
    create(index(:email_presets, [:job_type]))
    create(index(:email_presets, [:state]))
  end

  def down do
    drop(index(:email_presets, [:type]))
    drop(index(:email_presets, [:job_type]))
    drop(index(:email_presets, [:state]))
  end
end
