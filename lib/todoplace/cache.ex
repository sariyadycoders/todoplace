defmodule Todoplace.Cache do
  import Ecto.Query
  alias Todoplace.Accounts
  alias Todoplace.{Repo, Organization}

  @redis_name :redix
  @session_ttl 1 * 24 * 60 * 60
  # @session_ttl 15 * 60

  def set_user_data(session_token, user_data) do
    key = "session:#{session_token}"

    case get_key_data(key) do
      {:ok, nil} ->
        put_key_value(key, user_data)

      {:ok, binary} ->
        :erlang.binary_to_term(binary)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_user_data(session_token) do
    key = "session:#{session_token}"

    with {:ok, binary} when not is_nil(binary) <- get_key_data(key),
         %{} = decoded_data <- :erlang.binary_to_term(binary),
         true <- valid_data?(decoded_data) do
      decoded_data
    else
      _error ->
        refresh_current_user_cache(session_token)
    end
  end

  def update_log_in_user_cache(session_token) do
    key = "session:#{session_token}"

    case get_key_data(key) do
      # when  login then cache get updated data
      {:ok, nil} -> :nothing
      {:ok, binary} -> refresh_current_user_cache(session_token)
      {:error, reason} -> {:error, reason}
    end
  end

  def refresh_organization_cache(id) do
    delete_organization_data(id)
    get_organization_data(id)
  end

  def refresh_current_user_cache(session_token) do
    delete_user_data(session_token)
    get_user_from_db_and_set(session_token)
  end

  def update_user_data(session_token, new_user_data) do
    key = "session:#{session_token}"

    case get_ttl(key) do
      ttl when is_integer(ttl) and ttl > 0 ->
        put_key_value(key, new_user_data, ttl)

      :no_ttl ->
        {:error, "No TTL set or key does not exist"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_organization_data(id) do
    key = "organization_#{id}"
    delete_key_data(key)
  end

  def delete_user_data(session_token) do
    key = "session:#{session_token}"
    delete_key_data(key)
  end

  def set_organization_data(org) do
    "organization_#{org.id}"
    |> put_key_value(org)
  end

  def get_organization_data(id) do
    "organization_#{id}"
    |> get_key_data()
    |> case do
      {:ok, nil} -> get_organization_from_db_and_set(id)
      {:ok, binary} -> :erlang.binary_to_term(binary)
      {:error, reason} -> {:error, reason}
    end
  end

  def get_organizations([]), do: []

  def get_organizations(user_org_ids) do
    org_keys = Enum.map(user_org_ids, &"organization_#{&1}")
    cached_orgs = get_multiple_key_data(org_keys)

    uncached_org_ids =
      Enum.zip(user_org_ids, cached_orgs)
      |> Enum.filter(fn {_, org} -> is_nil(org) end)
      |> Enum.map(fn {id, _} -> id end)

    missing_orgs = fetch_organizations_from_db(uncached_org_ids)

    # Caching
    missing_orgs
    |> Enum.each(fn org -> set_organization_data(org) end)

    org_keys
    |> get_multiple_key_data()
    |> Enum.map(fn binary -> :erlang.binary_to_term(binary) end)
  end

  def get_all_apps() do
    case get_key_data("apps") do
      {:ok, nil} ->
        apps = Todoplace.Apps.get_all_apps()
        put_key_value("apps", apps)
        apps

      {:ok, binary} ->
        :erlang.binary_to_term(binary)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Get Time to Live against key
  defp get_ttl(key) do
    case Redix.command(@redis_name, ["TTL", key]) do
      {:ok, ttl} when ttl > 0 -> ttl
      {:ok, _ttl} -> :no_ttl
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_key_value(key, value, ttl \\ @session_ttl) do
    {:ok, "OK"} =
      Redix.command(@redis_name, ["SETEX", key, ttl, :erlang.term_to_binary(value)])
  end

  def get_key_data(key) do
    Redix.command(@redis_name, ["GET", key])
  end

  def get_multiple_key_data(keys) do
    {:ok, cached_orgs} = Redix.command(@redis_name, ["MGET" | keys])
    cached_orgs
  end

  defp delete_key_data(key) do
    Redix.command(@redis_name, ["DEL", key])
  end

  defp fetch_organizations_from_db(ids) do
    Repo.all(
      from o in Organization,
        where: o.id in ^ids,
        preload: [organization_users: [user: [:user_organizations]]]
    )
  end

  defp get_organization_from_db_and_set(nil), do: nil

  defp get_organization_from_db_and_set(id) do
    with %Organization{} = org <- Accounts.get_orgnization(id),
         {:ok, "OK"} <- set_organization_data(org) do
      org
    else
      _ -> nil
    end
  end

  defp get_user_from_db_and_set(nil), do: nil

  defp get_user_from_db_and_set(session_token) do
    with %Accounts.User{} = user <- Accounts.get_user_by_session_token(session_token),
         %{} <-
           Enum.find(
             user.user_organizations,
             &(&1.organization_id == user.organization_id && &1.organization_id != :deleted)
           ),
         %{} = user_data <- make_user_params(user, session_token),
         {:ok, "OK"} <- set_user_data(session_token, user_data) do
      user_data
    else
      _ -> nil
    end
  end

  def get_user_from_db(session_token) do
    with %Accounts.User{} = user <- Accounts.get_user_by_session_token(session_token),
         %{} = user_data <- make_user_params(user, session_token) do
      user_data
    else
      _ -> nil
    end
  end

  def get_active_organization_ids(user) do
    user.user_organizations
    |> Enum.filter(&(&1.org_status == :active))
    |> Enum.map(& &1.organization_id)
  end

  def get_all_organization_ids(user) do
    user.user_organizations
    |> Enum.map(& &1.organization_id)
  end

  defp get_notification_count(user_id, organization_id) do
    count =
      Todoplace.Accounts.Notification
      |> where([n], n.user_id == ^user_id and n.organization_id == ^organization_id)
      |> Todoplace.Repo.aggregate(:count, :id)

    count
  end

  defp make_user_params(user, session_token) do
    user_organizations_ids = get_active_organization_ids(user)
    user_all_organizations_ids = get_all_organization_ids(user)

    notification_counts =
      Enum.map(user_organizations_ids, fn org_id ->
        {org_id, get_notification_count(user.id, org_id)}
      end)

    %{
      current_user: user,
      user_organizations_ids: user_organizations_ids,
      user_all_organizations_ids: user_all_organizations_ids,
      user_preferences: Todoplace.Accounts.User.get_user_preferences(user.id).settings,
      notification_counts: notification_counts,
      session_token: session_token
    }
  end

  defp valid_data?(%{
         current_user: user,
         user_organizations_ids: user_org_ids,
         user_all_organizations_ids: user_all_org_ids,
         user_preferences: user_preferences,
         notification_counts: notification_counts,
         session_token: token
       })
       when is_map(user) and is_map(user_preferences) and is_list(user_org_ids) and
              is_list(user_all_org_ids) and is_binary(token) do
    true
  end

  defp valid_data?(_), do: false
end
