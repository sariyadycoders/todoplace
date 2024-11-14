defmodule Todoplace.Workers.SendProposalReminder do
  @moduledoc false
  use Oban.Worker,
    unique: [period: :infinity, states: ~w[available scheduled executing retryable]a]

  @impl Oban.Worker
  def perform(_), do: Todoplace.ProposalReminder.deliver_all()
end
