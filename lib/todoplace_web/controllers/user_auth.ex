defmodule TodoplaceWeb.UserAuth do
  @moduledoc false
  use TodoplaceWeb, :html
  import Phoenix.Component, except: [assign: 3]
  import Plug.Conn
  import Phoenix.Controller

  alias Todoplace.Accounts

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_todoplace_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    device_id = Map.get(params, "device_id")
    user = user |> Todoplace.Repo.preload([:user_organizations])
    token = Accounts.generate_user_session_token(user, Map.get(params, "device_id"))
    #  Todoplace.Cache.set_user_data(token, user)

    redirect_to = get_session(conn, :user_return_to) || signed_in_path(conn)

    redirect_to =
      Enum.all?(user.user_organizations, fn item ->
        item.org_status == :deleted
      end)
      |> all_deleted_organizations(redirect_to)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_resp_cookie("redirect_welcome_route", redirect_welcome_route?(user), http_only: false)
    |> put_session(:live_socket_id, "users_sessions:#{device_id}:#{Base.url_encode64(token)}")
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: redirect_to)
  end

  defp all_deleted_organizations(true, _), do: "/create_organization"
  defp all_deleted_organizations(_, redirect_to), do: redirect_to

  @doc """
  Logs the user in from the admin panel.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user_from_admin(conn, user) do
    token = Accounts.generate_user_session_token(user)
    # Todoplace.Cache.set_user_data(token, user)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_resp_cookie("show_admin_banner", "true", http_only: false)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
    |> put_flash(:info, "Logged in as user from admin")
    |> redirect(to: "/home")
  end

  def redirect_welcome_route?(%{onboarding: %{welcome_count: count}}), do: to_string(count < 3)
  def redirect_welcome_route?(_user), do: to_string(true)

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out(conn, params \\ %{}) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_session_token(user_token, Map.get(params, "device_id"))

    if live_socket_id = get_session(conn, :live_socket_id) do
      TodoplaceWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect_to(params)
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    # user = user_token && Accounts.get_user_by_session_token(user_token)
    current_user_data = Todoplace.Cache.get_user_data(user_token)
    user = current_user_data && current_user_data.current_user

    conn
    |> assign(:current_user, user)
    |> assign(:user_token, user_token)
    |> assign(:current_user_data, current_user_data)
  end

  defp ensure_user_token(conn) do
    if user_token = get_session(conn, :user_token) do
      {user_token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if user_token = conn.cookies[@remember_me_cookie] do
        {user_token, put_session(conn, :user_token, user_token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    user =
      conn.assigns[:user_token] && Accounts.get_user_by_session_token(conn.assigns[:user_token])

    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      if user do
        conn
        |> redirect(to: ~p"/create_organization")
        |> halt()
      else
        conn
      end
    end
  end

  def deleted_organizations_user(conn, _opts) do
    user =
      conn.assigns[:user_token] && Accounts.get_user_by_session_token(conn.assigns[:user_token])

    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      if user do
        conn
        |> assign(:current_user, user)
      else
        conn
        |> redirect(to: ~p"/users/log_in")
        |> halt()
      end
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    user =
      conn.assigns[:user_token] && Accounts.get_user_by_session_token(conn.assigns[:user_token])

    (conn.assigns[:current_user] || user)
    |> handle_user_authentication(user, conn)
  end

  defp handle_user_authentication(%{}, _, conn), do: conn

  defp handle_user_authentication(_, nil, conn) do
    conn
    |> put_flash(:error, "You must log in to access this page.")
    |> maybe_store_return_to()
    |> redirect(to: ~p"/users/log_in")
    |> halt()
  end

  defp handle_user_authentication(_, %{}, conn) do
    conn
    |> redirect(to: ~p"/create_organization")
    |> halt()
  end

  @doc """
  Used for /finances route that require the can_manage_finances flag
  for photographer to be true to manage the finances.
  """
  def photographer_can_manage_finances(conn, _opts) do
    if FunWithFlags.enabled?(:can_manage_finances, for: conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_flash(:error, "You are not authorized to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp redirect_to(conn, %{type: :standard, client_link_hash: hash}) do
    redirect(conn, to: ~p"/gallery/#{hash}")
  end

  defp redirect_to(conn, %{albums: [%{client_link_hash: hash}]}) do
    redirect(conn, to: ~p"/album/#{hash}")
  end

  defp redirect_to(conn, _) do
    redirect(conn, to: "/")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(conn), do: ~p"/home"
end
