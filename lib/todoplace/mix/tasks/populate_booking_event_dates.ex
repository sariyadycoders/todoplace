defmodule Mix.Tasks.PopulateBookingEventDates do
  @moduledoc """
    Mix task for populating booking_event dates ---> booking_event_dates
  """

  use Mix.Task

  import Ecto.Query, warn: false

  alias Todoplace.{Repo, BookingEvent, BookingEventDatesMigration, BookingEventDate}

  def run(_) do
    load_app()

    batch_size = 5
    offset = 0

    # Loop until no more records are fetched
    loop_through_batches(batch_size, offset)
    # migrate_booking_events()
  end

  defp loop_through_batches(batch_size, offset) do
    subquery = from(d in BookingEventDate, select: d.booking_event_id)

    batch =
      from(e in BookingEvent,
        where: not is_nil(e.old_dates),
        where: e.id not in subquery(subquery),
        limit: ^batch_size,
        offset: ^offset
      )
      |> Repo.all()

    if length(batch) > 0 do
      migrate_booking_events(batch)
      # process_batch(batch)
      loop_through_batches(batch_size, offset + batch_size)
    end
  end

  # defp process_batch(booking_events) do
  #   multi = Ecto.Multi.new()

  #   Enum.reduce(booking_events, multi, fn booking_event, multi_acc ->
  #     booking_event_dates =
  #       Enum.map(
  #         booking_event.old_dates,
  #         &BookingEventDatesMigration.available_times(booking_event, &1.date)
  #       )

  #     # Generating a unique key for each insert operation
  #     multi_key = "insert_booking_event_date_#{booking_event.id}"

  #     # Adding an insert_all operation to Ecto.Multi for each booking event
  #     Ecto.Multi.insert_all(multi_acc, multi_key, BookingEventDate, booking_event_dates)
  #   end)
  #   |> Repo.transaction()
  # end

  defp migrate_booking_events(booking_events) do
    booking_events
    |> Enum.map(&migrate_old_events(&1))
  end

  # defp get_all_bookings() do
  #   from(e in BookingEvent, where: not is_nil(e.old_dates))
  #   |> Repo.all()
  # end

  defp migrate_old_events(event) do
    booking_event_dates =
      Enum.map(event.old_dates, fn date ->
        BookingEventDatesMigration.available_times(event, date.date)
      end)

    Repo.insert_all(BookingEventDate, booking_event_dates)
  end

  defp load_app do
    if System.get_env("MIX_ENV") != "prod" do
      Mix.Task.run("app.start")
    end
  end
end
