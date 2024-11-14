defmodule Todoplace.RewardfulAffiliate.Impl do
  @moduledoc """
  An Elixir module for interacting with the Rewardful
  API. Contains code to get a create and get an affiliate, and log them in with a magic link
  """

  alias Todoplace.{
    RewardfulAffiliate,
    Accounts.User,
    RewardfulAffiliate.Mapper
  }

  @behaviour RewardfulAffiliate

  @config Application.compile_env(:todoplace, :rewardful)
  @client_secret @config[:client_secret]
  @base_url @config[:base_url]
  @campaign_id @config[:campaign_id]
  @allow_stripe_customer_id @config[:allow_stripe_customer_id]

  @type result(x) :: {:ok, x} | {:error, String.t()}

  @spec create_affiliate(map()) :: result(map())
  @doc """
  Creates an affiliate
  """
  @impl RewardfulAffiliate
  def create_affiliate(%{email: email, stripe_customer_id: stripe_customer_id} = user) do
    params =
      URI.encode_query(%{
        first_name: User.first_name(user),
        last_name: User.last_name(user),
        email: email,
        stripe_customer_id: if(@allow_stripe_customer_id, do: stripe_customer_id),
        campaign_id: @campaign_id,
        receive_new_commission_notifications: true
      })

    HTTPoison.post!(
      "#{@base_url}/affiliates",
      params,
      headers(),
      basic_auth()
    )
    |> Mapper.handle_response()
    |> Mapper.to_user_save()
  end

  @spec generate_magic_link(map()) :: {:error, binary()} | {:ok, binary()}
  @doc """
  Generates a magic link to auto log the user in
  """
  @impl RewardfulAffiliate
  def generate_magic_link(%{
        rewardful_affiliate: %{affiliate_id: id}
      }) do
    HTTPoison.get!(
      "#{@base_url}/affiliates/#{id}/sso",
      [],
      basic_auth()
    )
    |> Mapper.handle_response()
    |> Mapper.to_sso_url()
  end

  defp basic_auth(),
    do: [hackney: [basic_auth: {@client_secret, ""}]]

  defp headers(),
    do: ["Content-Type": "application/x-www-form-urlencoded"]
end
