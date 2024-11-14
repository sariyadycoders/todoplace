defmodule Todoplace.PaymentSchedule do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_schedules" do
    field :price, Money.Ecto.Map.Type
    field :due_at, :utc_datetime
    field :reminded_at, :utc_datetime
    field :paid_at, :utc_datetime
    field :description, :string
    field :stripe_payment_intent_id, :string
    field :stripe_session_id, :string
    field :type, :string, default: "stripe"
    field :is_with_cash, :boolean
    belongs_to :job, Todoplace.Job

    timestamps(type: :utc_datetime)
  end

  @update_attrs [
    :paid_at,
    :type,
    :price,
    :due_at,
    :job_id,
    :description
  ]

  # @required_attrs [:paid_at, :type, :price]
  def changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, ~w[price due_at description job_id]a)
    |> validate_required(~w[price due_at description job_id]a)
  end

  def add_payment_changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, @update_attrs)
    |> validate_required(~w[price paid_at]a)
  end

  def stripe_ids_changeset(
        %__MODULE__{} = payment_schedule,
        stripe_payment_intent_id,
        stripe_session_id
      ) do
    change(payment_schedule, %{
      stripe_payment_intent_id: stripe_payment_intent_id,
      stripe_session_id: stripe_session_id,
      type: "stripe"
    })
  end

  def paid_changeset(payment_schedule) do
    change(payment_schedule, %{paid_at: DateTime.truncate(DateTime.utc_now(), :second)})
  end

  def reminded_at_changeset(payment_schedule) do
    change(payment_schedule, %{reminded_at: DateTime.truncate(DateTime.utc_now(), :second)})
  end

  def paid?(%__MODULE__{paid_at: paid_at}), do: paid_at != nil
  def is_with_cash?(%__MODULE__{is_with_cash: is_with_cash}), do: is_with_cash == true

  @type t :: %__MODULE__{
          id: integer(),
          price: Money.t(),
          due_at: DateTime.t(),
          reminded_at: DateTime.t(),
          paid_at: DateTime.t(),
          description: String.t(),
          stripe_payment_intent_id: String.t(),
          stripe_session_id: String.t(),
          type: String.t(),
          is_with_cash: boolean(),
          job_id: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
end
