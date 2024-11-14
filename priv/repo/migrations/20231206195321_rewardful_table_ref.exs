defmodule Todoplace.Repo.Migrations.RewardfulTableRef do
  use Ecto.Migration

  def up do
    alter table(:users) do
      remove(:rewardful_affiliate)
    end

    create table(:rewardful_affiliates) do
      add(:affiliate_id, :string)
      add(:affiliate_token, :string)
      add(:user_id, references(:users, on_delete: :nothing), null: false)

      timestamps()
    end

    execute(
      """
        insert into rewardful_affiliates (user_id, inserted_at, updated_at)
        select users.id, now(), now()
        from users
      """,
      ""
    )
  end

  def down do
    drop(table(:rewardful_affiliates))

    alter table(:users) do
      add(:rewardful_affiliate, :map,
        default: fragment("jsonb_build_object('id', '', 'token', '')")
      )
    end
  end
end
