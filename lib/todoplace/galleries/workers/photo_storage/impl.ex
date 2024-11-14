defmodule Todoplace.Galleries.Workers.PhotoStorage.Impl do
  @moduledoc false

  alias Todoplace.Galleries.Workers.PhotoStorage
  alias GoogleApi.Storage.V1.{Api.Objects, Connection, Model.Object}
  @behaviour PhotoStorage

  @bucket Application.compile_env(:todoplace, :photo_storage_bucket)

  @impl PhotoStorage
  def path_to_url(path, bucket \\ @bucket) do
    path =
      path
      |> Path.split()
      |> List.update_at(-1, &URI.encode/1)
      |> Path.join()

    GCSSign.sign_url_v4(gcp_credentials(), bucket: bucket, key: path, expires_in: 604_800)
  end

  @impl PhotoStorage
  def params_for_upload(options) do
    {:ok, params} = GCSSign.sign_post_policy_v4(gcp_credentials(), options)
    params
  end

  @impl PhotoStorage
  def delete(path, bucket \\ @bucket)

  def delete(nil, _), do: :ignored

  def delete(path, bucket) do
    {:ok, _} = Objects.storage_objects_delete(connection(), bucket, path)
    :ok
  rescue
    _ -> :error
  end

  @impl PhotoStorage
  def get(path), do: get(path, @bucket)

  @impl PhotoStorage
  def get(path, bucket),
    do: Objects.storage_objects_get(connection(), bucket, path)

  def get_binary(path), do: Tesla.get(path_to_url(path))

  @impl PhotoStorage
  def initiate_resumable(name, content_type) do
    Objects.storage_objects_insert_resumable(
      connection(),
      @bucket,
      "resumable",
      name: name,
      body: %Object{contentType: content_type}
    )
  end

  @impl PhotoStorage
  def initiate_resumable(name, content_type, origin) do
    Objects.storage_objects_insert_resumable(
      connection(origin),
      @bucket,
      "resumable",
      name: name,
      body: %Object{
        contentType: content_type
      }
    )
  end

  @impl PhotoStorage
  def insert(path, object) do
    Objects.storage_objects_insert_iodata(
      connection(),
      @bucket,
      "multipart",
      %Object{},
      object,
      name: path
    )
  end

  @impl PhotoStorage
  defdelegate continue_resumable(url, body, opts), to: Connection, as: :put

  defp gcp_credentials() do
    {:ok, private_key} = Goth.Config.get("private_key")
    {:ok, client_id} = Goth.Config.get("client_id")

    %{
      "private_key" => private_key,
      "client_id" => client_id
    }
  end

  defp connection(origin) do
    {:ok, token} = handle_credentials()

    Tesla.client([
      {Tesla.Middleware.Headers, [{"Origin", origin}, {"authorization", "Bearer #{token.token}"}]}
    ])
  end

  defp connection do
    {:ok, token} = handle_credentials()

    Connection.new(token.token)
  end

  def handle_credentials do
    credentials = Application.get_env(:todoplace, :goth_json) |> Jason.decode!()

    Goth.start_link(
      name: Todoplace.Goth,
      source:
        {:service_account, credentials,
         scopes: ["https://www.googleapis.com/auth/cloud-platform"]}
    )

    Goth.fetch(Todoplace.Goth)
  end
end
