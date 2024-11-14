
defmodule Todoplace.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      timestamps()
    end

    create unique_index(:roles, [:name])
  end
end
