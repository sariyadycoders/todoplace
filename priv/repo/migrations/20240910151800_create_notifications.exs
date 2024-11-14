defmodule Todoplace.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      add :title, :string, null: false
      add :body, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    # Optionally, create an index on the user_id for faster queries
    create index(:notifications, [:user_id])
  end
end
