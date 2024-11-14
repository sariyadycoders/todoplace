defmodule Todoplace.RewardfulAffiliate do
  @moduledoc "behavior of affiliate"

  @callback create_affiliate(map()) :: {:ok, map} | {:error, String.t()}

  @callback generate_magic_link(map()) ::
              {:ok, String.t()} | {:error, String.t()}

  def create_affiliate(user), do: impl().create_affiliate(user)
  def generate_magic_link(user), do: impl().generate_magic_link(user)

  defp impl, do: Application.get_env(:todoplace, :rewardful_affiliate)
end
