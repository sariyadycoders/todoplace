defmodule Todoplace.Galleries.PhotoProcessing.ProcessingManager do
  @moduledoc """
  Sends Tasks for Cloud Function to process
  """
  require Logger

  alias Todoplace.Galleries.Photo
  alias Todoplace.Galleries.PhotoProcessing.Context
  alias Todoplace.Galleries.PhotoProcessing.Waiter
  alias Todoplace.Galleries.Watermark
  alias Todoplace.GlobalSettings.Gallery, as: GSGallery

  def start(photo, watermark \\ nil)

  def start(%Photo{} = photo, nil) do
    Context.simple_task_by_photo(photo) |> send()
    Waiter.start_tracking(photo.gallery_id, photo.id)
  end

  def start(%Photo{} = photo, watermark) do
    Context.full_task_by_photo(photo, watermark) |> send()
    Waiter.start_tracking(photo.gallery_id, photo.id)
  end

  def update_watermark(%Photo{} = photo, %Watermark{} = watermark) do
    Context.watermark_task_by_photo(photo, watermark) |> send()
    Waiter.start_tracking(photo.gallery_id, photo.id)
  end

  def update_watermark(%GSGallery.Photo{} = global_photo) do
    Context.watermark_task_by_global_settings(global_photo)
    |> send()
  end

  def process_cover_photo(path),
    do: Context.task_by_cover_photo(path) |> send()

  defp send(task) do
    topic = Application.get_env(:todoplace, :photo_processing_input_topic)
    {:ok, project_id} = Goth.Config.get("project_id")
    {:ok, token} = Todoplace.Galleries.Workers.PhotoStorage.Impl.handle_credentials()

    result =
      Kane.Message.publish(
        %Kane{project_id: project_id, token: token},
        %Kane.Message{data: task},
        %Kane.Topic{name: topic}
      )

    case result do
      {:ok, _return} ->
        Logger.debug("Sent photo to processing #{inspect(task)}")

      err ->
        Logger.error("Error sending photo to processing #{inspect(err)} \n #{inspect(task)}")
    end
  end
end
