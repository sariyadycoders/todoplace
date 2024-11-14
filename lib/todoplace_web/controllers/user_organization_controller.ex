defmodule TodoplaceWeb.UserOrganizationController do
  use TodoplaceWeb, :controller

  alias Todoplace.Accounts
  alias Todoplace.Accounts.User

  action_fallback TodoplaceWeb.FallbackController


  def show(conn, %{"id" => user_id}) do
    organizations = Accounts.user_active_organization(user_id, "joined")
    render(conn, :user_organization, organizations: organizations)
  end

  def update(conn, %{"id" => id, "user" => user_params}) do

    with {:ok, %User{} = user} <- Accounts.update_user(id, user_params) do
      render(conn, :show, user: user)
    end
  end
end
