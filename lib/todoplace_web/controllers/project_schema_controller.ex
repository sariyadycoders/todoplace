defmodule TodoplaceWeb.ProjectSchemaController do
  use TodoplaceWeb, :controller
  alias Todoplace.Repo
  alias Ecto.Association.BelongsTo
  alias Ecto.Association.Has

  def get_table_names(conn, _params) do
    project_schema =
      get_all_table_names()
      |> Jason.encode!()

    conn
    |> middleware(project_schema)
    |> send_resp(200, project_schema)
  end

  def get_table_info(conn, %{"table_name" => table_name}) do
    project_table_info =
      %{
        "table_name" => table_name,
        "table_module" => "#{get_schema_module_for_table(table_name) |> inspect}",
        "columns" => get_table_columns(table_name)
      }
      |> Jason.encode!()

    conn
    |> middleware(project_table_info)
    |> send_resp(200, project_table_info)
  end

  def get_all_tables_info(conn, _params) do
    all_tables_info = get_all_tables_info() |> Jason.encode!()

    conn
    |> middleware(all_tables_info)
    |> send_resp(200, all_tables_info)
  end

  def get_tables_relationship(conn, %{"schema_one" => schema_one, "schema_two" => schema_two}) do
    project_table_relationships =
      get_relationship_type(schema_one, schema_two)
      |> Jason.encode!()

    conn
    |> middleware(project_table_relationships)
    |> send_resp(200, project_table_relationships)
  end

  def get_table_info_from_module_name(conn, %{"module_name" => module_name}) do
    table_name = table_name(module_name)

    project_table_info =
      %{
        "table_name" => table_name,
        "table_module" => module_name,
        "columns" => get_table_columns(table_name)
      }
      |> Jason.encode!()

    conn
    |> middleware(project_table_info)
    |> send_resp(200, project_table_info)
  end

  def get_project_file_structure(conn, %{"app_name" => app_name, "folder_type" => folder_type}) do
    project_file_structure = get_project_folder_names(folder_type, app_name) |> Jason.encode!()

    conn
    |> middleware(project_file_structure)
    |> send_resp(200, project_file_structure)
  end

  def get_project_context(conn, _params) do
    project_context = Todoplace.Shared.get_app_params() |> Jason.encode!()

    conn
    |> middleware(project_context)
    |> send_resp(200, project_context)
  end

  def get_sidebar(conn, _params) do
    web_module = Todoplace.Shared.get_app_params() |> Map.get(:web_module)

    sidebar_map = TodoplaceWeb.Shared.Sidebar.side_nav(%{}, %{}) |> Jason.encode!()

    conn
    |> middleware(sidebar_map)
    |> send_resp(200, sidebar_map)
  end

  def ping(conn, _params) do
    resp = "ok" |> Jason.encode!()

    conn
    |> middleware(resp)
    |> send_resp(200, resp)
  end

  defp middleware(conn, body) do
    body_signature =
      hash_http_body(body, "secret")

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("Sha256-Signature", body_signature)
  end

  defp get_all_tables_info do
    query = """
    SELECT table_name, column_name
    FROM
    information_schema.columns
    WHERE
    table_schema = 'public'
    ORDER BY
    table_name,
    ordinal_position;
    """

    Repo.query!(query)
    |> Map.get(:rows)
    |> Enum.group_by(fn [table_name, _column_name] -> table_name end)
    |> Enum.map(fn {table_name, columns} ->
      %{name: table_name, fields: Enum.map(columns, fn [_table, column] -> column end)}
    end)
  end

  defp get_all_table_names do
    query = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_type = 'BASE TABLE'
    """

    Repo.query!(query)
    |> Map.get(:rows)
    |> List.flatten()
  end

  defp hash_http_body(body, secret) do
    hmac_sha256_hash = :crypto.mac(:hmac, :sha256, secret, body)

    hmac_sha256_hash
    |> Base.encode64()
  end

  defp get_table_columns(table_name) do
    query = """
    SELECT column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = $1
    ORDER BY ordinal_position;
    """

    Repo.query!(query, [table_name])
    |> Map.get(:rows)
    |> Enum.map(fn [column_name, _data_type, _is_nullable, _column_default] ->
      column_name
    end)
  end

  defp get_schema_module_for_table(table_name) do
    :code.all_loaded()
    |> Enum.flat_map(fn {module, _bin} -> [module] end)
    |> Enum.filter(&is_schema_module/1)
    |> Enum.find(fn mod ->
      module_has_table?(mod, table_name)
    end)
  end

  defp get_relationship_type(schema1, schema2) do
    assoc1 = inspect_relationship(schema1, schema2)
    assoc2 = inspect_relationship(schema2, schema1)

    case {assoc1, assoc2} do
      {%BelongsTo{}, _} -> "belongs-to"
      {%Has{cardinality: :one}, _} -> "has-one"
      {%Has{cardinality: :many}, _} -> "has-many"
      {%Ecto.Association.HasThrough{cardinality: :many}, _} -> "many-to-many"
      {_, _} -> "No Specific"
    end
  end

  defp inspect_relationship(schema1, schema2) do
    list_of_associations =
      schema1.__schema__(:associations)

    second_table_name =
      table_name(schema2)
      |> singular_table_name(list_of_associations)
      |> String.to_atom()

    schema1.__schema__(:association, second_table_name)
  end

  def table_name(schema_module) do
    schema_module.__schema__(:source)
  end

  defp is_schema_module(module) do
    try do
      module.__schema__(:source)
      true
    rescue
      _ -> false
    end
  end

  defp module_has_table?(module, table_name) do
    try do
      module.__schema__(:source) == table_name
    rescue
      _ -> false
    end
  end

  defp singular_table_name(table_name, list_of_associations) do
    if table_name do
      # Basic singularization rules
      atom_name = table_name |> String.to_atom()

      if atom_name in list_of_associations do
        table_name
      else
        cond do
          String.ends_with?(table_name, "ies") ->
            String.replace_suffix(table_name, "ies", "y")

          String.ends_with?(table_name, "es") ->
            String.replace_suffix(table_name, "es", "e")

          String.ends_with?(table_name, "s") ->
            String.replace_suffix(table_name, "s", "")

          true ->
            table_name
        end
      end
    else
      "random_name"
    end
  end

  def get_project_folder_names(folder_type, app_name \\ "todo_meter") do
    app_params = Todoplace.Shared.get_app_params()

    path =
      case folder_type do
        # "projects" -> @projects_dir
        "apps" -> "./#{app_params.web_path}/"
        "modules" -> "./#{app_params.web_path}/#{app_name}/live/"
      end

    get_project_folders(path, folder_type)
  end

  def get_project_folders(path, folder_type) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&File.dir?(Path.join(path, &1)))
        |> filter_project_folders(folder_type)

      {:error, reason} ->
        IO.puts("Failed to list directories: #{reason}")
        []
    end
  end

  defp filter_project_folders(folders, folder_type) do
    case folder_type do
      "apps" ->
        folders --
          ["channels", "components", "controllers", "live", "plugs", "views", "templates"]

      _ ->
        folders
    end
  end
end
