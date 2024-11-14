defmodule Todoplace.Galleries.PhotoProcessing.Context do
  @moduledoc """
  Operates structures Cloud Function uses to get task and output result

  Task ---> Cloud Function ---> Context(Task, Artifacts)

  Task represents image processing task sent by BE to Cloud Function
  Context consists of Task and Artifacts.
  Cloud Function returns Context.
  Artifacts is the structure Cloud Function puts its inner state and results(like aspect ratio)
  """

  alias Todoplace.Galleries
  alias Todoplace.Galleries.CoverPhoto
  alias Todoplace.Galleries.Photo
  alias Todoplace.GlobalSettings
  alias GlobalSettings.Gallery, as: GSGallery
  alias Todoplace.Galleries.Watermark

  @bucket Application.compile_env(:todoplace, :photo_storage_bucket)
  @output_topic Application.compile_env(:todoplace, :photo_processing_output_topic)

  def simple_task_by_photo(%Photo{} = photo) do
    %{
      "photoId" => photo.id,
      "bucket" => @bucket,
      "pubSubTopic" => @output_topic,
      "originalPath" => photo.original_url,
      "previewPath" => Photo.preview_path(photo)
    }
  end

  def full_task_by_photo(%Photo{} = photo, %Watermark{} = watermark) do
    gallery = Galleries.get_gallery!(watermark.gallery_id)
    watermark_path = path(gallery, watermark)

    %{
      "photoId" => photo.id,
      "bucket" => @bucket,
      "pubSubTopic" => @output_topic,
      "originalPath" => photo.original_url,
      "previewPath" => Photo.preview_path(photo),
      "watermarkedPreviewPath" => Photo.watermarked_preview_path(photo),
      "watermarkedOriginalPath" => Photo.watermarked_path(photo),
      "watermarkPath" => watermark_path,
      "watermarkText" => watermark.type == :text && watermark.text
    }
  end

  def watermark_task_by_global_settings(%GSGallery.Photo{} = photo) do
    watermark_path = GSGallery.watermark_path(photo.organization_id)

    %{
      "globalWatermarkPreview" => true,
      "isSavePreview" => photo.is_save_preview,
      "photoId" => photo.id,
      "organizationId" => photo.organization_id,
      "bucket" => @bucket,
      "pubSubTopic" => @output_topic,
      "originalPath" => photo.original_url,
      "previewPath" => nil,
      "watermarkedPreviewPath" => GSGallery.watermarked_path(),
      "watermarkedOriginalPath" => GSGallery.watermarked_path(),
      "watermarkPath" => photo.watermark_type == :image && watermark_path,
      "watermarkText" => photo.watermark_type == :text && photo.text
    }
  end

  def watermark_task_by_photo(%Photo{} = photo, %Watermark{} = watermark) do
    photo
    |> full_task_by_photo(watermark)
    |> Map.drop(["previewPath"])
  end

  def task_by_cover_photo(path) do
    %{
      "processCoverPhoto" => true,
      "bucket" => @bucket,
      "pubSubTopic" => @output_topic,
      "originalPath" => path
    }
  end

  def save_processed(context), do: do_save_processed(context)

  defp do_save_processed(%{
         "task" => %{
           "photoId" => photo_id,
           "previewPath" => preview_url,
           "watermarkedPreviewPath" => watermarked_preview_path,
           "watermarkedOriginalPath" => watermark_path
         },
         "artifacts" => %{
           "isPreviewUploaded" => true,
           "aspectRatio" => aspect_ratio,
           "height" => height,
           "width" => width,
           "isWatermarkedUploaded" => true
         }
       }) do
    Galleries.update_photo(photo_id, %{
      aspect_ratio: aspect_ratio,
      height: height,
      width: width,
      preview_url: preview_url,
      watermarked_url: watermark_path,
      watermarked_preview_url: watermarked_preview_path
    })
  end

  defp do_save_processed(%{
         "task" => %{"photoId" => photo_id, "previewPath" => preview_url},
         "artifacts" => %{
           "isPreviewUploaded" => true,
           "aspectRatio" => aspect_ratio,
           "height" => height,
           "width" => width
         }
       }) do
    Galleries.update_photo(photo_id, %{
      aspect_ratio: aspect_ratio,
      height: height,
      width: width,
      preview_url: preview_url
    })
  end

  defp do_save_processed(%{
         "task" => %{
           "photoId" => photo_id,
           "watermarkedPreviewPath" => watermarked_preview_path,
           "watermarkedOriginalPath" => watermark_path
         },
         "artifacts" => %{
           "isWatermarkedUploaded" => true
         }
       }) do
    Galleries.update_photo(photo_id, %{
      watermarked_url: watermark_path,
      watermarked_preview_url: watermarked_preview_path
    })
  end

  defp do_save_processed(%{"task" => %{"photoId" => photo_id}}),
    do: Galleries.update_photo(photo_id, %{})

  defp do_save_processed(%{
         "task" => %{
           "processCoverPhoto" => true,
           "originalPath" => path
         },
         "artifacts" => %{
           "aspectRatio" => aspect_ratio,
           "width" => width,
           "height" => height
         }
       }) do
    path
    |> CoverPhoto.get_gallery_id_from_path()
    |> Galleries.get_gallery!()
    |> Galleries.save_gallery_cover_photo(%{
      cover_photo: %{id: path, aspect_ratio: aspect_ratio, width: width, height: height}
    })
    |> case do
      {:ok, %{cover_photo: photo}} -> {:ok, photo}
      error -> error
    end
  end

  def notify_processed(context, %Photo{} = photo) do
    Galleries.broadcast(%{id: photo.gallery_id}, {:photo_processed, context, photo})
  rescue
    _err ->
      :ignored
  end

  def notify_processed(context, %CoverPhoto{} = photo) do
    Phoenix.PubSub.broadcast(
      Todoplace.PubSub,
      "gallery:#{photo.gallery_id}",
      {:cover_photo_processed, context, photo}
    )
  rescue
    _err ->
      :ignored
  end

  def notify_processed(_), do: :ignored

  defp path(%{id: id}, %{type: :image}), do: Watermark.watermark_path(id)
  defp path(_gallery, _), do: nil
end
