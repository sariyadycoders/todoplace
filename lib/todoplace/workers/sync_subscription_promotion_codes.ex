defmodule Todoplace.Workers.SyncSubscriptionPromotionCodes do
  @moduledoc false
  use Oban.Worker,
    unique: [period: :infinity, states: ~w[available scheduled executing retryable]a]

  @impl Oban.Worker
  def perform(_) do
    Todoplace.Subscriptions.sync_subscription_promotion_codes()
  end
end
