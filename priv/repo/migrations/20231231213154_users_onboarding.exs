defmodule Todoplace.Repo.Migrations.UsersOnboarding do
  use Ecto.Migration

  def change do
    create table(:users_onboarding) do
      add(:user_id, references(:users), null: false)
      add(:completed_at, :utc_datetime)
      add(:slug, :string, null: false)
      add(:group, :string, null: false)
      timestamps()
    end

    create(unique_index(:users_onboarding, [:user_id, :slug, :group]))
    create(index(:users_onboarding, [:user_id, :group]))
  end
end
