defmodule Todoplace.Clients do
  @moduledoc "context module for clients"
  import Ecto.Query
  alias Todoplace.{Repo, Client, ClientTag}

  def client_by_email(organization_id, email) do
    from(c in Client, where: c.email == ^email and c.organization_id == ^organization_id)
    |> Repo.one()
  end

  def find_all_by(user: user) do
    clients_by_user(user)
    |> Repo.all()
  end

  def find_all_by(params) do
    find_all_query(params)
    |> where([client], is_nil(client.archived_at))
  end

  def find_clients_count(params) do
    find_all_query(params)
    |> Repo.all()
    |> Enum.count()
  end

  def find_all_by_pagination(
        user: user,
        filters: opts,
        pagination: %{limit: limit, offset: offset}
      ) do
    query = find_all_query(user: user, filters: opts)

    from(c in query,
      limit: ^limit,
      offset: ^offset
    )
  end

  def find_count_by(user: user) do
    clients_by_user(user)
    |> Repo.aggregate(:count)
  end

  def new_client_changeset(attrs, organization_id) do
    attrs
    |> Map.put("organization_id", organization_id)
    |> Client.create_client_changeset()
  end

  def edit_client_changeset(client, attrs) do
    Client.edit_client_changeset(client, attrs)
  end

  def save_new_client(attrs, organization_id) do
    new_client_changeset(attrs, organization_id) |> Repo.insert()
  end

  def update_client(client, attrs) do
    edit_client_changeset(client, attrs) |> Repo.update()
  end

  def archive_client(id) do
    Repo.get(Client, id)
    |> Client.archive_changeset()
    |> Repo.update()
  end

  def unarchive_client(id) do
    Repo.get(Client, id)
    |> Client.unarchive_changeset()
    |> Repo.update()
  end

  def get_client_tags(client_id) do
    from(tag in ClientTag,
      where: tag.client_id == ^client_id
    )
    |> Repo.all()
  end

  def delete_tag(client_id, name) do
    {:ok, _tag} =
      from(tag in ClientTag,
        where: tag.client_id == ^client_id and tag.name == ^name
      )
      |> Repo.one()
      |> Repo.delete()
  end

  def get_client_query(user, opts),
    do:
      Client
      |> preload([:tags, :jobs])
      |> where(^conditions(user, opts))

  def get_client(user, opts) do
    get_client_query(user, opts)
    |> Repo.one()
  end

  def get_recent_clients(user) do
    from(c in Client,
      where: c.organization_id == ^user.organization_id and is_nil(c.archived_at),
      order_by: [desc: c.inserted_at],
      limit: 6
    )
    |> Repo.all()
  end

  def client_tags(client) do
    (Enum.map(client.jobs, & &1.type)
     |> Enum.uniq()) ++
      Enum.map(client.tags, & &1.name)
  end

  def get_client_orders_query(client_id) do
    from(c in Client,
      preload: [jobs: [galleries: [orders: [:intent, :digitals, :products]]]],
      where: c.id == ^client_id
    )
  end

  def get_client!(client_id), do: Repo.get!(Client, client_id)
  def fetch_multiple(client_ids), do: where(Client, [c], c.id in ^client_ids) |> Repo.all()

  def search(search_phrase, _clients) when search_phrase in ["", nil], do: []

  def search(search_phrase, clients) do
    clients
    |> Enum.filter(&client_matches?(&1, search_phrase))
  end

  defp find_all_query(
         user: user,
         filters: %{sort_by: sort_by, sort_direction: sort_direction} = opts
       ) do
    from(client in Client,
      preload: [:tags, :jobs],
      left_join: jobs in assoc(client, :jobs),
      left_join: job_status in assoc(jobs, :job_status),
      where: client.organization_id == ^user.organization_id,
      where: ^filters_where(opts),
      where: ^filters_status(opts),
      group_by: client.id,
      order_by: ^filter_order_by(sort_by, sort_direction)
    )
  end

  defp conditions(user, opts) do
    id_filter = Keyword.get(opts, :id, false)
    email_filter = Keyword.get(opts, :email, false)

    conditions =
      dynamic([c], c.organization_id == ^user.organization_id and is_nil(c.archived_at))

    conditions =
      if id_filter,
        do: dynamic([c], c.id == ^id_filter and ^conditions),
        else: conditions

    if email_filter,
      do: dynamic([c], c.email == ^email_filter and ^conditions),
      else: conditions
  end

  defp filters_where(opts) do
    Enum.reduce(opts, dynamic(true), fn
      {:type, "all"}, dynamic ->
        dynamic

      {:type, value}, dynamic ->
        dynamic(
          [client, jobs, job_status],
          ^dynamic and client.id == jobs.client_id and jobs.type == ^value
        )

      {:search_phrase, nil}, dynamic ->
        dynamic

      {:search_phrase, search_phrase}, dynamic ->
        search_phrase = "%#{search_phrase}%"

        dynamic(
          [client, jobs, job_status],
          ^dynamic and
            (ilike(client.name, ^search_phrase) or
               ilike(client.email, ^search_phrase) or
               ilike(client.phone, ^search_phrase))
        )

      {_, _}, dynamic ->
        # Not a where parameter
        dynamic
    end)
  end

  defp filters_status(opts) do
    Enum.reduce(opts, dynamic(true), fn
      {:status, value}, dynamic ->
        case value do
          "past_jobs" ->
            filter_past_jobs(dynamic)

          "active_jobs" ->
            filter_active_jobs(dynamic)

          "leads" ->
            filter_leads(dynamic)

          "archived_clients" ->
            filter_archived_clients(dynamic)

          "all" ->
            filter_all_clients(dynamic)

          _ ->
            dynamic
        end

      _any, dynamic ->
        # Not a where parameter
        dynamic
    end)
  end

  defp filter_past_jobs(dynamic) do
    dynamic(
      [client, jobs, job_status],
      ^dynamic and client.id == jobs.client_id and
        not job_status.is_lead and
        job_status.current_status == :completed
    )
  end

  defp filter_active_jobs(dynamic) do
    dynamic(
      [client, jobs, job_status],
      ^dynamic and client.id == jobs.client_id and
        not job_status.is_lead and
        job_status.current_status not in [:completed, :archived]
    )
  end

  defp filter_leads(dynamic) do
    dynamic(
      [client, jobs, job_status],
      ^dynamic and client.id == jobs.client_id and job_status.is_lead and
        is_nil(jobs.archived_at)
    )
  end

  defp filter_archived_clients(dynamic) do
    dynamic(
      [client],
      ^dynamic and not is_nil(client.archived_at)
    )
  end

  defp filter_all_clients(dynamic) do
    dynamic(
      [client],
      ^dynamic and is_nil(client.archived_at)
    )
  end

  # returned dynamic with join binding
  defp filter_order_by(:id, order),
    do: [{order, dynamic([client, jobs], count(field(jobs, :id)))}]

  defp filter_order_by(column, order) do
    [{order, dynamic([client], field(client, ^column))}]
  end

  defp clients_by_user(user) do
    from(c in Client,
      where: c.organization_id == ^user.organization_id and is_nil(c.archived_at),
      order_by: [asc: c.name, asc: c.email]
    )
  end

  defp client_matches?(client, query) do
    (client.name && do_match?(client.name, query)) ||
      (client.name && do_match?(List.last(String.split(client.name)), query)) ||
      do_match?(client.email, query) ||
      (client.phone && String.contains?(client.phone, query))
  end

  defp do_match?(data, query) do
    String.starts_with?(
      String.downcase(data),
      String.downcase(query)
    )
  end
end
