defmodule Todoplace.Repo.Migrations.Addroletousertable do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, default: "admin", null: false
    end
  end
end
