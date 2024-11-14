defmodule Todoplace.Repo.Migrations.AddLastVisitedPageToUsersOrganizations do
  use Ecto.Migration

  def change do
    alter table(:users_organizations) do
      add :last_visited_page, :string
    end
  end
end
