defmodule Todoplace.RewardfulAffiliate.Mapper do
  @moduledoc "Used to map response from rewardful api"

  def handle_response(%{status_code: 200, body: body}), do: {:ok, Jason.decode!(body)}

  def handle_response(%{status_code: _status_code, body: body}),
    do: {:error, Jason.decode!(body)}

  def to_user_save(response) do
    case response do
      {:ok,
       %{
         "id" => id,
         "links" => links
       }} ->
        {:ok, %{id: id, token: links |> List.first() |> Map.get("token")}}

      {:error, error} ->
        {:error, error}
    end
  end

  def to_sso_url(response) do
    case response do
      {:ok,
       %{
         "sso" => %{
           "url" => url
         }
       }} ->
        {:ok, url}

      {:error, error} ->
        {:error, error}
    end
  end
end
