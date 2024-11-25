defmodule TodoplaceWeb.UserAdminSessionController do
  use TodoplaceWeb, :controller

  alias Todoplace.Accounts
  alias TodoplaceWeb.UserAuth

  def create(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(user_id)

    # Not the most secure way to do this, Outside of hiding behind admin panel Plug
    # for the future, need to make a bit more secure
    if user do
      UserAuth.log_in_user_from_admin(conn, user)
    else
      render(conn, "new.html", error_message: "Something went wrong")
    end
  end
end

defmodule TodoplaceWeb.UserAdminSessionHTML do
  use TodoplaceWeb, :html
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]
  import TodoplaceWeb.ViewHelpers

  embed_templates "templates/*"
end
