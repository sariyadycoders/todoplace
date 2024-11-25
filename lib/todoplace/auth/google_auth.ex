defmodule Todoplace.Auth.GoogleAuth do
  @moduledoc """
  Module for generating Google OAuth tokens manually.
  """

  @audience "https://oauth2.googleapis.com/token"
  @token_url "https://oauth2.googleapis.com/token"
  @scope "https://www.googleapis.com/auth/firebase.messaging"
  @service_account_file Path.join([__DIR__, "todoplace-web-8ff07-b4dc07b48756.json"])

  alias JOSE.{JWK, JWS, JWT}

  # Load the service account key
  defp get_service_account_key() do
    @service_account_file
    |> File.read!()
    |> Jason.decode!()
  end

  # Generate a JWT signed with the service account's private key
  def generate_jwt() do
    service_account = get_service_account_key()
    now = DateTime.utc_now() |> DateTime.to_unix()

    claims = %{
      "iss" => service_account["client_email"],
      "scope" => @scope,
      "aud" => @audience,
      "iat" => now,
      "exp" => now + 3600
    }

    jwk = JWK.from_pem(service_account["private_key"])

    {_, jwt} = JWT.sign(jwk, %{"alg" => "RS256"}, claims) |> JWS.compact()
    {:ok, jwt}
  end

  # Exchange the JWT for an OAuth 2.0 access token
  def get_access_token() do
    {:ok, jwt} = generate_jwt()

    # Construct the body as a map
    body = %{
      "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
      "assertion" => jwt
    }

    # Convert the body to JSON
    encoded_body = Jason.encode!(body)

    headers = [
      {"Content-Type", "application/json"}
    ]

    case Tesla.post(@token_url, encoded_body, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)["access_token"]}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, %{status: status, error: Jason.decode!(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
