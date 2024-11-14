defmodule Todoplace.Repo.Migrations.AddDevicesInUserToken do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :devices, {:array, :string}, default: []
    end
  end
end
