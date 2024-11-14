defmodule Todoplace.BookingEventDates do
  @moduledoc "context module for booking events dates"

  alias Todoplace.{
    Repo,
    BookingEventDate,
    BookingEventDate.SlotBlock,
    SlotGenerator
  }

  alias Ecto.Changeset
  import Ecto.Query

  @spec create_booking_event_dates(params :: map()) ::
          {:ok, %{}} | {:error, Changeset.t()}
  def create_booking_event_dates(params) do
    %BookingEventDate{}
    |> BookingEventDate.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Retrieves a list of booking event dates associated with the given booking event ID.
  """
  @spec get_booking_events_dates(booking_event_id :: integer()) :: [map()]
  def get_booking_events_dates(booking_event_id),
    do: booking_events_dates_query([booking_event_id]) |> Repo.all()

  @doc """
  Retrieves a list of booking event dates associated with the specified booking event IDs that have the same date.
  """
  @spec get_booking_events_dates_with_same_date(
          booking_event_ids :: [integer()],
          date :: Date.t()
        ) :: [map()]
  def get_booking_events_dates_with_same_date(booking_event_ids, date) do
    booking_events_dates_query(booking_event_ids)
    |> where(date: ^date)
    |> Repo.all()
  end

  @doc "deletes a single booking_Event_date that has the given id"
  def delete_booking_event_date(date_id) do
    date_id
    |> get_booking_event_date()
    |> Repo.delete()
  end

  def get_booking_event_date(date_id) do
    date_id
    |> booking_event_date_query()
    |> Repo.one()
  end

  @doc """
  Constructs a database query for retrieving booking event dates
  associated with specific dates and a booking event ID.

  This function takes a list of `dates` and a `booking_event_id` and creates
  a query to fetch `BookingEventDate` records where the `date` matches one of
  the dates in the provided list and the `booking_event_id` matches the given
  `booking_event_id`.

  ## Example

  ```elixir
  iex> dates = [~D[2023-09-07], ~D[2023-09-08]]
  iex> booking_event_id = 123
  iex> repeat_dates_queryable(dates, booking_event_id)
  iex> Repo.all(query)
  """
  @spec repeat_dates_queryable(dates :: [Date.t()], booking_event_id :: integer()) ::
          Ecto.Query.t()
  def repeat_dates_queryable(dates, booking_event_id) do
    from(
      event_date in BookingEventDate,
      where: event_date.date in ^dates and event_date.booking_event_id == ^booking_event_id
    )
  end

  def update_slot_status(booking_event_date_id, slot_index, slot_update_args) do
    booking_event_date_id
    |> get_booking_event_date()
    |> BookingEventDate.update_slot_changeset(slot_index, slot_update_args)
    |> upsert_booking_event_date()
  end

  @doc """
  Upserts (Insert or Update) a booking event date into the database.

  ## Example

  ```elixir
  %BookingEventDate{
    id: 1,
    date: ~D[2023-09-07],
    # ... other fields
  }

  # Update an existing booking event date
  iex> changeset = BookingEventDate.changeset(existing_record, %{date: ~D[2023-09-08]})
  iex> {:ok, result} = upsert_booking_event_date(changeset)
  iex> result
  %BookingEventDate{
    id: 1,
    date: ~D[2023-09-08],
    # ... other updated fields
  }
  """
  @spec upsert_booking_event_date(changeset :: Changeset.t()) ::
          {:ok, map()} | {:error, Changeset.t()}
  def upsert_booking_event_date(changeset) do
    changeset |> Repo.insert_or_update()
  end

  @doc """
  Generates a list of Ecto changesets for inserting multiple `BookingEventDate` rows
  with specified repeat dates based on a provided changeset.

  # Generate changesets for multiple repeat dates
  iex> repeat_dates = [~D[2023-09-07], ~D[2023-09-08], ~D[2023-09-09]]
  iex> changesets = generate_rows_for_repeat_dates(common_changeset, repeat_dates)
  iex> Enum.each(changesets, fn changeset ->
  ...>   {:ok, result} = Repo.insert(changeset)
  ...>   result
  ...> end)
  """
  @default_repeat_on [
    %{day: "sun", active: true},
    %{day: "mon", active: false},
    %{day: "tue", active: false},
    %{day: "wed", active: false},
    %{day: "thu", active: false},
    %{day: "fri", active: false},
    %{day: "sat", active: false}
  ]

  @spec generate_rows_for_repeat_dates(
          changeset :: Changeset.t(),
          repeat_dates :: [Date.t()]
        ) :: [Changeset.t()]
  def generate_rows_for_repeat_dates(changeset, repeat_dates) do
    default_repeat_changeset = set_defaults_for_repeat_dates_changeset(changeset)

    Enum.map(repeat_dates, fn date ->
      default_repeat_changeset
      |> then(fn repeat_changeset ->
        slots =
          Enum.map(Changeset.get_field(repeat_changeset, :slots), fn slot ->
            slot
            |> Map.replace(:status, :open)
            |> Map.replace(:client_id, nil)
            |> Map.replace(:job_id, nil)
          end)

        Changeset.put_change(repeat_changeset, :slots, slots)
      end)
      |> Changeset.put_change(:repeat_on, @default_repeat_on)
      |> Changeset.put_change(:date, date)
      |> Changeset.apply_changes()
      |> prepare_params()
    end)
  end

  @doc """
  Transforms a list of slot blocks by applying a default transformation to each slot.
  ## Example

  ```elixir
  # Transform a list of slot blocks with default values
  iex> input_slots = [SlotBlock.t(), SlotBlock.t()]
  iex> transform_slots(input_slots)
  [SlotBlock.t(), SlotBlock.t()]

  ## Notes
  This function is useful for applying a consistent default transformation to a list of slot blocks.
  """
  @spec transform_slots(input_slots :: [SlotBlock.t()]) :: [SlotBlock.t()]
  def transform_slots(input_slots), do: Enum.map(input_slots, &transform_slot/1)

  @doc """
  Retrieves available time slots for booking within a BookingEventDate.
  ## Example
  iex> available_slots(booking_date, booking_event)
  [
    %SlotBlock{
      id: 1,
      booking_event_id: 123,
      booking_event_date_id: 1,
      start_time: "09:00",
      end_time: "11:00",
      # ... other fields
    },
    %SlotBlock{
      id: 2,
      booking_event_id: 123,
      booking_event_date_id: 1,
      start_time: "13:15",
      end_time: "15:15",
      # ... other fields
    },
    # ... more available slots
  ]
  """
  @spec available_slots(booking_date :: map(), booking_event :: map()) ::
          [SlotBlock.t()] | nil
  def available_slots(%BookingEventDate{} = booking_date, _booking_event) do
    duration = booking_date.session_length

    Enum.map(booking_date.time_blocks, fn %{start_time: start_time, end_time: end_time} ->
      SlotGenerator.generate_and_filter_slots(
        start_time,
        end_time,
        duration,
        booking_date.session_gap
      )
    end)
    |> Enum.filter(& &1)
    |> List.first()
  end

  @doc """
  Checks if any time slot for a given booking event on the specified dates is booked.

  This function checks if any time slot for a particular booking event, identified by `booking_event_id`,
  is booked on the specified list of `repeat_dates`. It queries the database for booking event dates
  associated with each date and checks if any of their time slots have a booking status of `:booked`..
  ## Example

  ```elixir
  iex> repeat_dates = [~D[2023-09-07], ~D[2023-09-08]]
  iex> booking_event_id = 123
  iex> is_booked_any_date?(repeat_dates, booking_event_id)
  true
  """
  @spec is_booked_any_date?(repeat_dates :: [Date.t()], booking_event_id :: integer()) ::
          boolean()
  def is_booked_any_date?(repeat_dates, booking_event_id) do
    booked? = fn %{slots: slots} -> Enum.any?(slots, &(&1.status in [:booked, :reserved])) end

    Enum.any?(repeat_dates, fn date ->
      [booking_event_id]
      |> get_booking_events_dates_with_same_date(date)
      |> Enum.any?(&booked?.(&1))
    end)
  end

  defp transform_slot(slot) do
    cond do
      slot.status in [:booked, :reserved] ->
        %SlotBlock{
          slot
          | client_id: nil,
            job_id: nil,
            status: :open
        }

      slot.status == :hidden ->
        %SlotBlock{slot | is_hide: true}

      true ->
        slot
    end
  end

  # Constructs a database query to retrieve booking event dates
  defp booking_events_dates_query(booking_event_ids) do
    from(event_date in BookingEventDate,
      where: event_date.booking_event_id in ^booking_event_ids,
      order_by: [desc: event_date.date]
    )
  end

  # Prepares and extracts parameters from an Ecto changeset for insertion or update.
  defp prepare_params(changeset) do
    changeset
    |> Map.from_struct()
    |> Map.drop([:id, :__meta__, :booking_event, :is_repeat, :organization_id, :repetition])
  end

  # Sets default values for a changeset representing a `BookingEventDate` record with repeat dates.
  defp set_defaults_for_repeat_dates_changeset(booking_event) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    booking_event
    |> Changeset.change(%{
      calendar: "",
      count_calendar: 1,
      stop_repeating: nil,
      is_repeat: false,
      repetition: false,
      inserted_at: now,
      updated_at: now
    })
  end

  defp booking_event_date_query(date_id),
    do:
      from(event_date in BookingEventDate,
        where: event_date.id == ^date_id
      )
end
