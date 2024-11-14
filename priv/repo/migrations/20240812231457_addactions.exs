defmodule Todoplace.Repo.Migrations.CreateActions do
  use Ecto.Migration

  def change do
    create table(:actions, primary_key: false) do
      add :action_name, :string, primary_key: true
      add :module_name, :string, null: false
      timestamps()
    end

    create unique_index(:actions, [:action_name])
    create table(:permissions, primary_key: false) do
      add :name, :string, primary_key: true
      timestamps()
    end

    create unique_index(:permissions, [:name])
    create table(:role_actions, primary_key: false) do
      add :role_id, :string, null: false
      add :action_id, :string, null: false
      add :permission_id, :string, null: false
      timestamps()
    end

    create index(:role_actions, [:role_id])
    create index(:role_actions, [:action_id])
    create index(:role_actions, [:permission_id])
    
    create unique_index(:role_actions, [:role_id, :action_id, :permission_id])
  end
end

