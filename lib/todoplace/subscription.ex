defmodule Todoplace.Subscription do
  @moduledoc "Schema db view for returning the current subscription"

  use Ecto.Schema
  alias Todoplace.{Accounts.User}

  @primary_key false
  schema "subscriptions" do
    field :cancel_at, :utc_datetime
    field :current_period_end, :utc_datetime
    field :current_period_start, :utc_datetime
    field :status, :string
    field :active, :boolean
    field :price, Money.Ecto.Amount.Type
    field :recurring_interval, :string
    field :stripe_subscription_id, :string
    belongs_to :user, User
  end
end
