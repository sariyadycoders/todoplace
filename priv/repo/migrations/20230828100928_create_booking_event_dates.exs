defmodule Todoplace.Repo.Migrations.CreateBookingEventDates do
  use Ecto.Migration

  @table :booking_event_dates
  def up do
    create table(@table) do
      add(:date, :date, null: true)
      add(:location, :string)
      add(:address, :string)
      add(:session_length, :integer, null: false)
      add(:session_gap, :integer)
      add(:time_blocks, :map, null: false)
      add(:slots, :map, null: false)
      add(:calendar, :string)
      add(:count_calendar, :integer)
      add(:repeat_on, :map)
      add(:stop_repeating, :date)
      add(:occurrences, :integer, default: 0)

      add(:booking_event_id, references(:booking_events, on_delete: :nothing), null: false)
      timestamps()
    end

    create(index(@table, [:booking_event_id]))
  end

  def down do
    drop(table(@table))
  end
end
