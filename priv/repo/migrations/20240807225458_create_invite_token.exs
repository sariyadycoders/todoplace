defmodule Todoplace.Repo.Migrations.CreateInviteTokens do
  use Ecto.Migration

  def change do
    create table(:invite_tokens) do
      add :token, :string, null: false
      add :email, :string, null: false
      add :organization_id, :integer, null: false
      add :expires_at, :naive_datetime, null: false
      add :used, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:invite_tokens, [:token])
    create index(:invite_tokens, [:organization_id])
  end
end
