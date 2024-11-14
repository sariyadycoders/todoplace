defmodule Todoplace.Workers.SendShootReminder do
  @moduledoc false
  use Oban.Worker,
    unique: [period: :infinity, states: ~w[available scheduled executing retryable]a]

  @impl Oban.Worker
  def perform(_), do: Todoplace.ShootReminder.deliver_all(TodoplaceWeb.Helpers)
end
