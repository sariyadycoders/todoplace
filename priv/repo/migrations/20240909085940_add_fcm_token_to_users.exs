defmodule Todoplace.Repo.Migrations.AddFcmTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :fcm_token, :string
    end
  end
end
