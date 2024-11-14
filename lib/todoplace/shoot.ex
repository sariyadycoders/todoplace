defmodule Todoplace.Shoot do
  @moduledoc false
  use Ecto.Schema
  alias Todoplace.{NylasDetail, Repo}
  import Ecto.{Changeset, Query}

  @config Application.compile_env(:todoplace, :nylas)
  @todoplace_tag @config[:todoplace_tag]

  @locations ~w[studio on_location home]a
  @durations [
    2,
    5,
    10,
    15,
    20,
    30,
    45,
    60,
    90,
    120,
    180,
    240,
    300,
    360,
    420,
    480,
    540,
    600,
    660,
    720
  ]

  @spec locations :: [:home | :on_location | :studio]
  def locations(), do: @locations

  def durations(), do: @durations

  schema "shoots" do
    field :duration_minutes, :integer
    field :location, Ecto.Enum, values: @locations
    field :name, :string
    field :notes, :string
    field :starts_at, :utc_datetime
    field :reminded_at, :utc_datetime
    field :thanked_at, :utc_datetime
    field :address, :string
    field :external_event_id, :string
    belongs_to(:job, Todoplace.Job)

    timestamps()
  end

  def changeset_for_import_job(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :starts_at,
      :duration_minutes,
      :name,
      :location,
      :job_id,
      :address,
      :external_event_id
    ])
    |> validate_required([:starts_at, :duration_minutes, :name, :location])
    |> validate_inclusion(:location, @locations)
    |> validate_inclusion(:duration_minutes, @durations)
  end

  def changeset_for_create_gallery(%__MODULE__{} = shoot, attrs \\ %{}) do
    shoot
    |> cast(attrs, [:starts_at, :job_id, :external_event_id])
    |> validate_required([:starts_at])
  end

  @attrs ~w(starts_at duration_minutes name notes address external_event_id)a
  @required_attrs ~w(starts_at duration_minutes name)a

  def create_booking_event_shoot_changeset(shoot \\ %__MODULE__{}, attrs) do
    shoot
    |> cast(attrs, @attrs ++ [:job_id])
    |> validate_required(@required_attrs)
    |> validate_inclusion(:duration_minutes, @durations)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @attrs ++ [:job_id, :location])
    |> validate_required(@required_attrs ++ [:location, :job_id])
    |> validate_inclusion(:location, @locations)
    |> validate_inclusion(:duration_minutes, @durations)
  end

  def update_changeset(%__MODULE__{} = shoot, attrs) do
    shoot
    |> cast(attrs, @attrs ++ [:location])
    |> validate_required(@required_attrs ++ [:location])
    |> validate_inclusion(:location, @locations)
    |> validate_inclusion(:duration_minutes, @durations)
  end

  def reminded_at_changeset(%__MODULE__{} = shoot) do
    shoot |> change(reminded_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def thanked_at_changeset(%__MODULE__{} = shoot) do
    shoot |> change(thanked_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def by_starts_at(query \\ __MODULE__) do
    query |> order_by(asc: :starts_at)
  end

  def for_job(job_id) do
    __MODULE__ |> where(job_id: ^job_id) |> by_starts_at()
  end

  def update_shoot_time_address!(%__MODULE__{} = shoot, starts_at, address) do
    shoot |> change(starts_at: starts_at, address: address) |> Repo.update!()
  end

  def apply_limit(query \\ __MODULE__, limit) when is_integer(limit) do
    query |> limit(^limit)
  end

  @doc """
  Map external event by taking Shoot and NylasDetail to insert or update external event.
  """
  def map_event(
        %__MODULE__{
          duration_minutes: duration_minutes,
          name: name,
          notes: notes,
          starts_at: starts_at,
          address: address,
          external_event_id: external_event_id,
          job: %{client: client}
        },
        %NylasDetail{external_calendar_rw_id: calendar_id} = nylas,
        action \\ :insert
      ) do
    %{user: %{time_zone: timezone}} = nylas |> Repo.preload(:user)

    end_time = starts_at |> DateTime.add(duration_minutes * 60) |> DateTime.to_unix()

    event = %{
      when: %{
        start_time: starts_at |> DateTime.to_unix(),
        end_time: end_time,
        start_timezone: timezone,
        end_timezone: timezone
      },
      location: address,
      title: name,
      description: "Client: " <> client.name <> " " <> set_notes(notes)
    }

    case action do
      :insert -> Map.put(event, :calendar_id, calendar_id)
      :update -> Map.put(event, :id, external_event_id)
    end
  end

  defp set_notes(nil), do: "\n#{@todoplace_tag}\n"
  defp set_notes(notes), do: notes <> set_notes(nil)

  @type t :: %__MODULE__{
          id: integer(),
          duration_minutes: integer(),
          location: String.t(),
          name: String.t(),
          notes: String.t(),
          external_event_id: String.t(),
          reminded_at: DateTime.t(),
          thanked_at: DateTime.t(),
          starts_at: DateTime.t(),
          job_id: integer(),
          address: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
end
