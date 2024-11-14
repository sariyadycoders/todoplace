defmodule Todoplace.Workers.SendCampaign do
  @moduledoc "Background job to send campaign emails"
  use Oban.Worker, queue: :campaigns

  def perform(%Oban.Job{args: %{"id" => id}}) do
    Todoplace.Marketing.send_campaign_mail(id)
    :ok
  end
end
