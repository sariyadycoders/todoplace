defmodule Mix.Tasks.CreateRewardfulAffiliates do
  @moduledoc false

  alias Todoplace.{Accounts.User, Repo, Rewardful, RewardfulAffiliate}
  import Ecto.Query

  require Logger

  use Mix.Task

  @shortdoc "Create affiliates for all users"
  def run(_) do
    load_app()

    from(u in User)
    |> Repo.all()
    |> Repo.preload(:rewardful_affiliate)
    |> Enum.each(fn user ->
      with {:ok, data} <- RewardfulAffiliate.create_affiliate(user),
           {:ok, user} <-
             Rewardful.changeset(%{
               affiliate_id: data.id,
               affiliate_token: data.token,
               user_id: user.id
             })
             |> Repo.insert() do
        Logger.info("Affiliate created for #{user.id}")
      else
        {:error, error} ->
          Logger.error("Error creating affiliate for #{user.id}: #{inspect(error)}")
      end
    end)
  end

  defp load_app do
    if System.get_env("MIX_ENV") != "prod" do
      Mix.Task.run("app.start")
    end
  end
end
