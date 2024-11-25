defmodule TodoplaceWeb.UserSessionController do
  use TodoplaceWeb, :controller

  alias Todoplace.Accounts
  alias Todoplace.Galleries
  alias Todoplace.Repo
  alias TodoplaceWeb.UserAuth

  def create(%{req_cookies: cookies} = conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params
    device_id = cookies |> Map.get("user_agent") |> URI.decode_www_form()

    token = Map.get(user_params, "token")

    # Get the organization_id from the token if it exists
    organization_id =
      if token do
        case Todoplace.InviteToken.get_by_token(token) do
          nil -> nil
          {:ok, invitation} -> invitation.organization_id
        end
      end

    # Check if the user exists
    if user = Accounts.get_user_by_email_and_password(email, password) do
      # Log in the user

      # If organization_id is present, associate the user with the organization
      if organization_id do
        # Update user with organization_id
        {:ok, _user} = Accounts.update_user_organization(user.id, organization_id)

        # Insert entry into users_organizations table
        case Todoplace.Organization.insert_user_organization_association(organization_id, user.id) do
          :ok ->
            UserAuth.log_in_user(conn, user, %{"device_id" => device_id})

          {:error, reason} ->
            # Handle insertion error if needed
            render(conn, "new.html", error_message: "failed to join organization try again")
        end
      else
        UserAuth.log_in_user(conn, user, %{"device_id" => device_id})
      end
    else
      # Render error if user credentials are invalid
      render(conn, "new.html", error_message: "Invalid email or password")
    end
  end

  def delete(conn, %{"client_link_hash" => hash}) do
    gallery =
      hash
      |> Galleries.get_gallery_by_hash!()
      |> Repo.preload([:albums])

    conn
    |> delete_resp_cookie("show_admin_banner")
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out(gallery)
  end

  def delete(%{req_cookies: cookies} = conn, _params) do
    device_id = Map.get(cookies, "user_agent") |> URI.decode_www_form()

    conn
    |> delete_resp_cookie("show_admin_banner")
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out(%{"device_id" => device_id})
  end
end

defmodule TodoplaceWeb.UserSessionHTML do
  use TodoplaceWeb, :html
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]
  import TodoplaceWeb.ViewHelpers

  embed_templates "templates/*"
end
