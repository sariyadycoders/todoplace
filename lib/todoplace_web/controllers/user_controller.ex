defmodule TodoplaceWeb.UserController do
  use TodoplaceWeb, :controller  # This imports Phoenix.Controller functions, including json/3

  alias Todoplace.Accounts
  alias Todoplace.Repo

  def update_fcm_token(conn, %{"fcm_token" => fcm_token, "user_id" => user_id}) do
    user = Repo.get!(Accounts.User, user_id)
    changeset = Accounts.User.fcm_token_changeset(user, %{"fcm_token" => fcm_token})

    case Repo.update(changeset) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "FCM token updated successfully"})  # Returning JSON response with conn
      {:error, _changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to update FCM token"})
    end
  end
end
