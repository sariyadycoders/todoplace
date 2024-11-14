defmodule Todoplace.Repo.Migrations.AddIsRepeatingToBookingEvents do
  use Ecto.Migration

  @table "email_schedules"
  def up do
  end

  def down do
    check =
      "(job_id IS NOT NULL AND gallery_id IS NULL) or (gallery_id IS NOT NULL AND job_id IS NULL)"

    create(constraint(@table, :job_gallery_constraint, check: check))
  end
end
