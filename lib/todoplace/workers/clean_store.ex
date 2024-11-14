defmodule Todoplace.Workers.CleanStore do
  @moduledoc "Background job to clear obsolete files in storage"
  use Oban.Worker, queue: :storage

  require Logger

  alias Todoplace.Galleries.Workers.PhotoStorage

  def perform(%Oban.Job{args: %{"path" => path}}) when nil != path do
    PhotoStorage.delete(path)
    :ok
  end

  def perform(x) do
    Logger.warning("Unknown job format #{inspect(x)}")
    :ok
  end
end
