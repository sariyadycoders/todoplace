defmodule TodoplaceWeb.FCM do
  @moduledoc """
  Module for sending messages via Firebase Cloud Messaging (FCM).
  """

  @fcm_url "https://fcm.googleapis.com/v1/projects/todoplace-web-8ff07/messages:send"

  def send_message(access_token, token, title, body) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"}
    ]

    message =
      %{
        "message" => %{
          "token" => token,
          "notification" => %{
            "title" => title,
            "body" => body
          }
        }
      }
      |> Jason.encode!()

    case HTTPoison.post(@fcm_url, message, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        IO.puts("Successfully sent message: #{body}")

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        IO.puts("Failed to send message. Status: #{status}, Response: #{body}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts("HTTP request failed: #{reason}")
    end
  end
end
