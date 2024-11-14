defmodule Todoplace.BookingEventDate do
  @moduledoc """
  This module defines the schema for booking event dates, including embedded schemas for time blocks, slot blocks, and repeat day blocks.
  """
  use Ecto.Schema

  import Ecto.Changeset
  alias Todoplace.{Client, Job, BookingEventDates, BookingEvents}

  defmodule TimeBlock do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:start_time, :time)
      field(:end_time, :time)
    end

    def changeset(time_block \\ %__MODULE__{}, attrs) do
      time_block
      |> cast(attrs, [:start_time, :end_time])
      |> validate_required([:start_time, :end_time])
      |> validate_end_time()
    end

    defp validate_end_time(changeset) do
      start_time = get_field(changeset, :start_time)
      end_time = get_field(changeset, :end_time)

      if start_time && end_time && Time.compare(start_time, end_time) == :gt do
        changeset |> add_error(:end_time, "cannot be before start time")
      else
        changeset
      end
    end
  end

  defmodule SlotBlock do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:slot_start, :time)
      field(:slot_end, :time)
      belongs_to(:client, Client)
      belongs_to(:job, Job)

      field(:status, Ecto.Enum,
        values: [:open, :booked, :reserved, :hidden, :break, :external_booked],
        default: :open
      )

      field(:is_hide, :boolean, default: false, virtual: true)
      field(:is_already_booked, :boolean, default: false, virtual: true)
    end

    @type t :: %__MODULE__{
            job_id: integer(),
            client_id: integer(),
            status: atom()
          }

    def changeset(slot_block \\ %__MODULE__{}, attrs) do
      slot_block
      |> cast(attrs, [
        :slot_start,
        :slot_end,
        :client_id,
        :job_id,
        :status,
        :is_hide,
        :is_already_booked
      ])
      |> validate_required([:slot_start, :slot_end])
      |> then(fn changeset ->
        cond do
          get_field(changeset, :is_hide) ->
            put_change(changeset, :status, :hidden)

          get_field(changeset, :status) == :break || get_field(changeset, :is_already_booked) ->
            changeset
            |> put_change(:status, :open)
            |> put_change(:job_id, nil)
            |> put_change(:client_id, nil)
            |> put_change(:is_already_booked, true)

          get_field(changeset, :status) not in [:booked, :reserved] ->
            changeset
            |> put_change(:status, :open)

          true ->
            changeset
        end
      end)
    end
  end

  defmodule RepeatDayBlock do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:day, :string)
      field(:active, :boolean, default: false)
    end

    def changeset(repeat_day \\ %__MODULE__{}, attrs) do
      repeat_day
      |> cast(attrs, [:day, :active])
      |> validate_required([:day, :active])
    end
  end

  schema "booking_event_dates" do
    field :date, :date
    field :session_gap, :integer
    field :session_length, :integer
    field :location, :string
    field :address, :string
    field :calendar, :string
    field :count_calendar, :integer, default: 1
    field :stop_repeating, :date
    field :occurrences, :integer, default: 0
    embeds_many :repeat_on, RepeatDayBlock, on_replace: :delete
    field :organization_id, :integer, virtual: true
    field :is_repeat, :boolean, default: false, virtual: true
    field :repetition, :boolean, default: false, virtual: true
    belongs_to :booking_event, Todoplace.BookingEvent
    embeds_many :time_blocks, TimeBlock, on_replace: :delete
    embeds_many :slots, SlotBlock, on_replace: :delete

    timestamps()
  end

  @required_attrs [
    :booking_event_id,
    :session_length,
    :address,
    :date
  ]

  @doc false
  def changeset(booking_event \\ %__MODULE__{}, attrs) do
    booking_event
    |> cast(attrs, [
      :date,
      :location,
      :address,
      :booking_event_id,
      :session_length,
      :session_gap,
      :count_calendar,
      :calendar,
      :stop_repeating,
      :occurrences,
      :is_repeat,
      :repetition,
      :organization_id
    ])
    |> cast_embed(:time_blocks, required: true)
    |> cast_embed(:slots, required: true)
    |> cast_embed(:repeat_on)
    |> validate_required(@required_attrs)
    |> validate_length(:time_blocks, min: 1)
    |> validate_length(:slots, min: 1)
    |> validate_time_blocks()
    |> set_default_repeat_on()
    |> validate_booking_event_date()
    |> then(fn changeset ->
      if get_field(changeset, :is_repeat) do
        changeset
        |> validate_required([:count_calendar, :calendar])
        |> validate_number(:count_calendar, less_than: 100, greater_than: 0)
        |> validate_stop_repeating()
      else
        changeset
      end
    end)
  end

  def duplicate_changeset(booking_event \\ %__MODULE__{}, attrs) do
    booking_event
    |> cast(attrs, [
      :location,
      :address,
      :booking_event_id,
      :session_length,
      :session_gap,
      :count_calendar,
      :calendar,
      :stop_repeating,
      :occurrences,
      :is_repeat,
      :repetition
    ])
    |> cast_embed(:time_blocks)
    |> cast_embed(:slots)
    |> cast_embed(:repeat_on)
    |> validate_required([:booking_event_id, :session_length])
    |> validate_length(:time_blocks, min: 1)
    |> validate_length(:slots, min: 1)
    |> validate_time_blocks()
    |> set_default_repeat_on()
    |> validate_booking_event_date()
    |> then(fn changeset ->
      if get_field(changeset, :is_repeat) do
        changeset
        |> validate_required([:count_calendar, :calendar])
        |> validate_stop_repeating()
      else
        changeset
      end
    end)
  end

  def update_slot_changeset(booking_event_date, slot_index, slot_update_args) do
    slot =
      booking_event_date.slots
      |> Enum.at(slot_index)
      |> Map.merge(slot_update_args)

    booking_event_date
    |> change(slots: List.replace_at(booking_event_date.slots, slot_index, slot))
  end

  # This is to validate whether a booking-event-date already exists within a booking-event
  defp validate_booking_event_date(changeset) do
    booking_event_id = get_field(changeset, :booking_event_id)

    if get_field(changeset, :date) do
      [date, booking_event_date_id] = get_fields(changeset, [:date, :id])

      booking_event_dates =
        BookingEventDates.get_booking_events_dates_with_same_date([booking_event_id], date)

      booking_event_dates =
        if booking_event_date_id,
          do:
            booking_event_dates
            |> Enum.filter(&(&1.id != booking_event_date_id)),
          else: booking_event_dates

      if Enum.any?(booking_event_dates),
        do: changeset |> add_error(:date, "is already selected"),
        else: changeset
    else
      changeset
    end
  end

  # Validates the `stop_repeating` field based on the `repetition` field.
  defp validate_stop_repeating(changeset) do
    repetition_value = get_field(changeset, :repetition)

    {key, value} = if repetition_value, do: {:stop_repeating, nil}, else: {:occurrences, 0}
    changeset = put_change(changeset, key, value)

    [occurrences, stop_repeating] = get_fields(changeset, [:occurrences, :stop_repeating])

    if occurrences == 0 and is_nil(stop_repeating),
      do: changeset |> add_error(:occurrences, "Either occurence or date should be selected"),
      else: changeset
  end

  # Validates the time blocks to ensure they do not overlap with existing blocks.
  defp validate_time_blocks(changeset) do
    [date, organization_id, current_time_block, date_id] =
      get_fields(changeset, [:date, :organization_id, :time_blocks, :id])

    if is_nil(date) do
      changeset
    else
      _overlap_times? =
        booking_date_time_block_overlap?(
          organization_id,
          date,
          current_time_block,
          date_id
        )

      changeset
    end
  end

  # Checks if there is any overlap between booking date time blocks and provided blocks.
  defp booking_date_time_block_overlap?(_organization_id, nil, _blocks, _event_date_id), do: false

  defp booking_date_time_block_overlap?(organization_id, date, blocks, event_date_id) do
    organization_id
    |> BookingEvents.get_all_booking_events()
    |> Enum.map(& &1.id)
    |> is_date_time_block_overlap?(date, blocks, event_date_id)
  end

  # Checks if there is any overlap between booking date time blocks and provided blocks.
  defp is_date_time_block_overlap?(booking_ids, date, blocks, date_id) do
    booking_ids
    |> BookingEventDates.get_booking_events_dates_with_same_date(date)
    |> Enum.reject(&(&1.id == date_id))
    |> Enum.flat_map(& &1.time_blocks)
    |> Enum.concat(blocks)
    |> Enum.sort_by(&{&1.start_time, &1.end_time})
    |> BookingEvents.overlap_time?()
  end

  # Sets default values for the `repeat_on` field if it is empty.
  @default_values [
    %{day: "sun", active: true},
    %{day: "mon", active: false},
    %{day: "tue", active: false},
    %{day: "wed", active: false},
    %{day: "thu", active: false},
    %{day: "fri", active: false},
    %{day: "sat", active: false}
  ]
  defp set_default_repeat_on(changeset) do
    repeat_on = changeset |> get_field(:repeat_on)

    cond do
      repeat_on |> Enum.empty?() ->
        put_change(changeset, :repeat_on, @default_values)

      repeat_on |> Enum.any?(& &1.active) ->
        changeset

      true ->
        add_error(changeset, :repeat_on, "must be selected")
    end
  end

  defp get_fields(changeset, keys) do
    for key <- keys, do: get_field(changeset, key)
  end
end
