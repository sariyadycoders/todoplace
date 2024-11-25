defmodule Todoplace.Repo.Migrations.CreateAppsTable do
  use Ecto.Migration

  def change do
    create table(:apps, primary_key: false) do
      add :id, :string, primary_key: true
      add :description, :text

      timestamps()
    end

    execute("""
      INSERT INTO apps (id, description, inserted_at, updated_at)
      VALUES
      ('picsello', 'Photography app', now(), now()),
      ('todometer', 'Tracking meter app', now(), now())
    """)
  end
end
