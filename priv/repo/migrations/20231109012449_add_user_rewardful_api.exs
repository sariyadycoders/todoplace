defmodule Todoplace.Repo.Migrations.AddUserRewardfulApi do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:rewardful_affiliate, :map,
        default: fragment("jsonb_build_object('id', '', 'token', '')")
      )
    end
  end
end
