defmodule Todoplace.Schema.Oban do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "oban_jobs" do
    field(:state, :string)
    field(:queue, :string)
    field(:worker, :string)
    field(:args, :map)
    field(:errors, {:array, :map})
    field(:attempt, :integer)
    field(:max_attempts, :integer)
    field(:priority, :integer)
    field(:tags, {:array, :string})
    field(:meta, :map)
    field(:attempted_by, {:array, :string})

    field(:inserted_at, :utc_datetime)
    field(:scheduled_at, :utc_datetime)
    field(:attempted_at, :utc_datetime)
    field(:completed_at, :utc_datetime)
    field(:cancelled_at, :utc_datetime)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :state,
      :queue,
      :worker,
      :args,
      :errors,
      :attempt,
      :max_attempts,
      :priority,
      :tags,
      :meta,
      :attempted_by,
      :inserted_at,
      :scheduled_at,
      :attempted_at,
      :completed_at,
      :cancelled_at
    ])
  end
end
