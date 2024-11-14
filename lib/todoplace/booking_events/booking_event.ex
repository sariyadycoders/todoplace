defmodule Todoplace.BookingEvent do
  use Ecto.Schema
  import Ecto.Changeset

  defmodule TimeBlock do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:start_time, :time)
      field(:end_time, :time)
      field(:is_hidden, :boolean, default: false)
      field(:is_break, :boolean, default: false)
      field(:is_booked, :boolean, default: false)
      field(:is_valid, :boolean, default: true, virtual: true)
    end

    def changeset(time_block \\ %__MODULE__{}, attrs) do
      time_block
      |> cast(attrs, [:start_time, :end_time, :is_hidden, :is_break, :is_booked, :is_valid])
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

  defmodule EventDate do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:date, :date)
      embeds_many :time_blocks, TimeBlock, on_replace: :delete
    end

    def changeset(event_date \\ %__MODULE__{}, attrs) do
      event_date
      |> cast(attrs, [:date])
      |> cast_embed(:time_blocks, required: true)
      |> validate_required([:date])
      |> validate_length(:time_blocks, min: 1)
      |> validate_time_blocks()
    end

    defp validate_time_blocks(changeset) do
      blocks = changeset |> get_field(:time_blocks)
      sort_blocks = Enum.sort_by(blocks, &{&1.start_time, &1.end_time})
      filter_blocks = Enum.filter(sort_blocks, fn block -> !block.is_break end)

      overlap_times =
        for(
          [
            %{end_time: %Time{} = previous_time},
            %{start_time: %Time{} = start_time}
          ] <-
            Enum.chunk_every(filter_blocks, 2, 1),
          do: Time.compare(previous_time, start_time) == :gt
        )
        |> Enum.any?()

      if overlap_times do
        changeset |> add_error(:time_blocks, "can't be overlapping")
      else
        changeset
      end
    end
  end

  # TODO: delete old_dates after the migration is done running.
  # Used this field to copy dates ---> old_dates and then data in old_dates ---> booking_event_date
  schema "booking_events" do
    field :name, :string
    field :description, :string
    field :buffer_minutes, :integer
    field :duration_minutes, :integer
    field :location, :string
    field :address, :string
    field :thumbnail_url, :string
    field :show_on_profile?, :boolean, default: false
    field :is_repeating, :boolean, default: false
    field :include_questionnaire?, :boolean, default: true
    field(:status, Ecto.Enum, values: [:active, :disabled, :archive])
    belongs_to :package_template, Todoplace.Package
    belongs_to :organization, Todoplace.Organization
    embeds_many :old_dates, EventDate, on_replace: :delete
    has_many :dates, Todoplace.BookingEventDate
    has_many :jobs, Todoplace.Job

    timestamps()
  end

  @doc false
  def changeset(booking_event \\ %__MODULE__{}, attrs, opts) do
    steps = [
      details: &update_details/2,
      package: &update_package_template/2,
      customize: &update_customize/2
    ]

    step = Keyword.get(opts, :step, :customize)

    Enum.reduce_while(steps, booking_event, fn {step_name, initializer}, changeset ->
      {if(step_name == step, do: :halt, else: :cont), initializer.(changeset, attrs)}
    end)
  end

  # create booking event with minimal info
  # def changeset(booking_event \\ %__MODULE__{}, attrs) do
  #   booking_event
  #   |> cast(attrs, [:name, :organization_id, :is_repeating])
  #   |> validate_required([:name, :organization_id])
  # end

  # changeset used to duplicate booking events with empty dates & time slots
  def duplicate_changeset(booking_event \\ %__MODULE__{}, attrs) do
    booking_event
    |> cast(attrs, [
      :name,
      :organization_id,
      :address,
      :description,
      :location,
      :package_template_id,
      :status,
      :thumbnail_url,
      :is_repeating
    ])
    |> validate_required([:name, :organization_id, :package_template_id])
  end

  def archive_changeset(%__MODULE__{} = booking_event) do
    booking_event |> change(status: :archive)
  end

  def disable_changeset(%__MODULE__{} = booking_event) do
    booking_event |> change(status: :disabled)
  end

  def enable_changeset(%__MODULE__{} = booking_event) do
    booking_event |> change(status: :active)
  end

  def update_customize(booking_event, attrs) do
    booking_event
    |> cast(attrs, [
      :name,
      :description,
      :thumbnail_url,
      :show_on_profile?
    ])
    |> validate_required([
      :description,
      :thumbnail_url
    ])
  end

  def update_package_template(booking_event, attrs) do
    booking_event
    |> cast(attrs, [:package_template_id, :include_questionnaire?])
    |> validate_required([:package_template_id])
  end

  defp update_details(booking_event, attrs) do
    booking_event
    |> cast(attrs, [
      :name,
      :location,
      :address,
      :duration_minutes,
      :buffer_minutes
    ])
    |> cast_assoc(:dates, required: true)
    |> validate_required([
      :name,
      :location,
      :address,
      :duration_minutes
    ])
    |> validate_length(:dates, min: 1)
    |> validate_dates()
  end

  defp validate_dates(changeset) do
    dates = changeset |> get_field(:dates)

    same_dates =
      dates
      |> Enum.map(& &1.date)
      |> Enum.filter(& &1)
      |> Enum.group_by(& &1)
      |> Map.values()
      |> Enum.all?(&(Enum.count(&1) == 1))

    if same_dates do
      changeset
    else
      changeset |> add_error(:dates, "can't be the same")
    end
  end
end
