defmodule TodoplaceWeb.RewardfulWebhooksController do
  use TodoplaceWeb, :controller

  alias Todoplace.{
    Repo,
    Rewardful
  }

  import Ecto.Query

  require Logger

  def parse(conn, params) do
    handle_event(params)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end

  defp handle_event(%{
         "event" => %{"type" => "affiliate_link.updated"},
         "object" => %{"affiliate_id" => affiliate_id, "token" => token}
       }) do
    with affiliate <- find_affiliate_by_affiliate_id(affiliate_id),
         {:ok, updated_affiliate} <-
           Rewardful.changeset(affiliate, %{
             affiliate_id: affiliate_id,
             affiliate_token: token
           })
           |> Repo.update() do
      Logger.info("[rewardful] Affiliate updated for affiliate_id #{updated_affiliate.id}")
    else
      nil ->
        Logger.info("[rewardful] Affiliate not found for affiliate_id #{affiliate_id}")

      {:error, error} ->
        Logger.error(
          "[rewardful] Error updating affiliate for affiliate_id #{affiliate_id} #{inspect(error)}"
        )
    end
  end

  defp handle_event(_), do: Logger.info("[rewardful] Unhandled event")

  defp find_affiliate_by_affiliate_id(affiliate_id) do
    from(ra in Rewardful,
      where: ra.affiliate_id == ^affiliate_id
    )
    |> Repo.one()
  end
end
