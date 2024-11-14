defmodule Todoplace.Workers.SendPaymentScheduleReminder do
  @moduledoc false
  use Oban.Worker,
    unique: [period: :infinity, states: ~w[available scheduled executing retryable]a]

  @impl Oban.Worker
  def perform(_) do
    if balance_due_emails_enabled?() do
      Todoplace.PaymentSchedules.deliver_reminders(TodoplaceWeb.Helpers)
    end

    :ok
  end

  defp balance_due_emails_enabled?,
    do: Enum.member?(Application.get_env(:todoplace, :feature_flags, []), :balance_due_emails)
end
