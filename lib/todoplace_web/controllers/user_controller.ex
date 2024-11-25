defmodule TodoplaceWeb.UserController do
  # This imports Phoenix.Controller functions, including json/3
  use TodoplaceWeb, :controller

  alias Todoplace.Accounts
  alias Todoplace.Repo

  def update_fcm_token(conn, %{"fcm_token" => fcm_token, "user_id" => user_id}) do
    user = Repo.get!(Accounts.User, user_id)
    changeset = Accounts.User.fcm_token_changeset(user, %{"fcm_token" => fcm_token})

    case Repo.update(changeset) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        # Returning JSON response with conn
        |> json(%{message: "FCM token updated successfully"})

      {:error, _changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to update FCM token"})
    end
  end
end
