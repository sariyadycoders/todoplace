defmodule Todoplace.Repo.Migrations.CreateUsersAuthMethods do
  use Ecto.Migration

  def change do
    create table(:users_auth_methods) do
      add :provider_user_id, :string
      add :user_id, references(:users, on_delete: :nothing)
      add :auth_method_name, references(:auth_methods, column: :name, type: :string, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:users_auth_methods, [:user_id])
    create index(:users_auth_methods, [:auth_method_name])
    create unique_index(:users_auth_methods, [:user_id, :auth_method_name, :provider_user_id])
  end
end
