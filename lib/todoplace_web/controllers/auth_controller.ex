defmodule TodoplaceWeb.AuthController do
  use TodoplaceWeb, :controller
  plug(Ueberauth)
  require Logger

  alias TodoplaceWeb.UserAuth

  def request(conn, _params) do
    render(conn, "", callback_url: Ueberauth.Strategy.Helpers.callback_url(conn))
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate.")
    |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}, req_cookies: cookies} = conn, _params) do
    device_id = cookies |> Map.get("user_agent") |> URI.decode_www_form()
    onboarding_flow_source =
      case Map.get(cookies, "onboarding_type") do
        nil -> []
        onboarding_type -> [onboarding_type]
      end

    case Todoplace.Accounts.user_from_auth(
           auth,
           cookies |> Map.get("time_zone"),
           &url(~p"/users/reset_password/#{&1}"),
           onboarding_flow_source
         ) do
      {:ok, user} ->
        conn
        |> delete_resp_cookie("onboarding_type")
        |> delete_resp_cookie("user_agent")
        |> UserAuth.log_in_user(user, %{"device_id" => device_id})

      {:error, changeset} ->
        Logger.info(fn ->
          "auth failed: " <> inspect(Ecto.Changeset.traverse_errors(changeset, & &1))
        end)

        conn
        |> put_flash(:error, "We're having trouble on our end. Please contact support.")
        |> redirect(to: "/")
    end
  end
end
