defmodule Todoplace.Repo.Migrations.AlterTableBookingEventsAddOrganizationId do
  use Ecto.Migration
  @table :booking_events
  def up do
    alter table(@table) do
      add(:organization_id, references(:organizations, on_delete: :nothing))
      modify(:location, :string, null: true)
      modify(:address, :string, null: true)
      modify(:duration_minutes, :integer, null: true)
      modify(:description, :text, null: true)
      modify(:thumbnail_url, :string, null: true)
      modify(:package_template_id, :integer, null: true)
      modify(:dates, :map, null: true)
    end

    create(index(@table, [:organization_id]))

    flush()

    execute("""
      update booking_events set organization_id = p.organization_id
      from packages p where p.id = booking_events.package_template_id;
    """)

    # execute("""
    #   update booking_events set organization_id = 1
    # """)
  end

  def down do
    alter table(@table) do
      remove(:organization_id)
      modify(:location, :string, null: false)
      modify(:address, :string, null: false)
      modify(:duration_minutes, :integer, null: false)
      modify(:description, :text, null: false)
      modify(:thumbnail_url, :string, null: false)
      modify(:package_template_id, :integer, null: false)
      modify(:dates, :map, null: false)
    end

    drop(index(@table, [:organization_id]))
  end
end
