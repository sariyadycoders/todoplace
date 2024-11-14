defmodule Todoplace.Photos do
  @moduledoc "context module for uploaded photos"

  import Ecto.Query, only: [from: 2, where: 3, order_by: 3]

  alias Ecto.Multi

  alias Todoplace.{
    Galleries,
    Galleries.Album,
    Cart.Digital,
    Galleries.Photo,
    Galleries.Watermark,
    Galleries.Workers.PhotoStorage,
    Orders,
    Repo
  }

  @gallery_icon "/images/gallery-icon.svg"
  @card_blank "/images/card_gray.png"

  def preview_url(%{watermarked: _} = photo, opts) do
    url =
      case Keyword.get(opts, :proofing_client_view?) do
        true -> preview_url(%{photo | watermarked: true})
        _ -> preview_url(photo)
      end

    with true <- url == @gallery_icon,
         true <- Keyword.get(opts, :blank, false) do
      @card_blank
    else
      _ -> url
    end
  end

  def preview_url(%{is_finals: true, preview_url: "" <> path}) do
    path_to_url(path)
  end

  def preview_url(%{watermarked: true, watermarked_preview_url: "" <> path}) do
    path_to_url(path)
  end

  def preview_url(%{preview_url: "" <> path}),
    do: path_to_url(path)

  def preview_url(_), do: @gallery_icon

  def original_url(%{original_url: path}), do: path_to_url(path)

  def get_album_name(photo) do
    photo = Repo.preload(photo, :album)
    if photo.album, do: photo.album.name, else: nil
  end

  def watermarked_query do
    watermark =
      from(watermark in Watermark,
        group_by: watermark.gallery_id,
        select: watermark.gallery_id
      )

    digital =
      from(digital in Digital,
        join: order in subquery(Orders.client_paid_query()),
        on: order.id == digital.order_id,
        join: photo in assoc(digital, :photo),
        group_by: [photo.gallery_id, photo.id],
        select: %{gallery_id: photo.gallery_id, photo_id: photo.id}
      )

    bundle_order =
      from(order in Orders.client_paid_query(),
        where: not is_nil(order.bundle_price),
        group_by: order.gallery_id,
        select: %{gallery_id: order.gallery_id}
      )

    photo_query =
      from(photo in active_photos(),
        left_join: watermarked in subquery(watermark),
        on: watermarked.gallery_id == photo.gallery_id,
        left_join: digital in subquery(digital),
        on: digital.gallery_id == photo.gallery_id and digital.photo_id == photo.id,
        left_join: bundle in subquery(bundle_order),
        on: bundle.gallery_id == photo.gallery_id,
        select: %{
          photo
          | watermarked:
              not is_nil(watermarked.gallery_id) and is_nil(digital.photo_id) and
                is_nil(bundle.gallery_id)
        }
      )

    photo_query =
      from(photo in photo_query,
        left_join: digital in subquery(digital),
        on: digital.photo_id == photo.id,
        select_merge: %{
          is_selected: digital.photo_id == photo.id
        }
      )

    from(photo in photo_query,
      left_join: album in Album,
      on: album.id == photo.album_id,
      select_merge: %{
        is_finals: album.is_finals
      }
    )
  end

  @doc """
  Gets a single photo by id.

  Returns nil if the Photo does not exist.

  ## Examples

      iex> get(123)
      %Photo{}

      iex> get(44545)
      nil

  """
  def get(id), do: Repo.get(watermarked_query(), id)

  def get!(gallery, id), do: Repo.get_by!(watermarked_query(), id: id, gallery_id: gallery.id)

  def toggle_liked(id) when is_number(id) do
    {1, [photo]} =
      from(photo in Photo,
        where: photo.id == ^id,
        update: [set: [client_liked: not photo.client_liked]],
        select: photo
      )
      |> Repo.update_all([])

    {:ok, photo}
  end

  def toggle_photographer_liked(id) when is_number(id) do
    case toggle_photographer_liked_query(id) do
      {_, photos} -> {:ok, List.first(photos)}
      _ -> {:error, "something went wrong"}
    end
  end

  defp toggle_photographer_liked_query(id) do
    from(photo in Photo,
      where: photo.id == ^id,
      update: [set: [is_photographer_liked: not photo.is_photographer_liked]],
      select: photo
    )
    |> Repo.update_all([])
  end

  @spec get_related(Photo.t(), favorites_only: boolean()) :: [Photo.t()]
  def get_related(%{gallery_id: gallery_id, id: photo_id} = photo, opts \\ []) do
    query = get_related_query(gallery_id, photo_id, photo)

    case Keyword.get(opts, :favorites_only) do
      true -> where(query, [photo], photo.client_liked == true)
      _ -> query
    end
    |> then(
      &case Keyword.get(opts, :album_id) do
        nil -> &1
        album_id -> where(&1, [photo], photo.album_id == ^album_id)
      end
    )
    |> Repo.all()
  end

  def get_related_query(gallery_id, photo_id, photo) do
    order_by =
      case photo.album_id do
        nil ->
          &order_by(&1, [photo], asc_nulls_first: photo.album_id, asc: photo.position)

        album_id ->
          &order_by(&1, [photo],
            desc_nulls_last: photo.album_id == ^album_id,
            asc: photo.album_id,
            asc: photo.position
          )
      end

    from(photo in watermarked_query(),
      where:
        photo.gallery_id == ^gallery_id and photo.id != ^photo_id and
          not is_nil(photo.height) and not is_nil(photo.width)
    )
    |> order_by.()
  end

  def active_photos, do: from(p in Photo, where: p.active == true)

  def update_photos_in_bulk(photos, new_values) when is_list(photos) and is_list(new_values) do
    new_values = Map.new(new_values, &{&1.id, &1})

    Enum.reduce(photos, Multi.new(), fn %{id: id} = photo, multi ->
      Multi.update(multi, id, Photo.update_changeset(photo, new_values[id]))
    end)
    |> Repo.transaction()
    |> then(fn
      {:ok, _} ->
        {:ok, Galleries.get_photos_by_ids(Map.keys(new_values))}

      error ->
        error
    end)
  end

  @headers [:photo_name, :size]
  def csv_content(photos, :base) do
    photos
    |> Enum.map(fn photo -> [photo.name, Size.humanize!(photo.size)] end)
    |> then(&[@headers | &1])
    |> CSV.encode()
    |> Enum.to_list()
    |> to_string()
  end

  def csv_content(photos, :lightroom) do
    # remove filename extensions, input -> [%{name: "abc.jpg"},  %{name: "xyz.jpg"}] and output will be like that "abc, xyz"
    content =
      photos
      |> Enum.map_join(", ", fn photo -> photo.name |> String.split(".") |> Enum.drop(-1) end)

    # Adobe Lightroom requires file names in a single column separated by commas
    # This is how you do that in CSV
    "\"#{content}\""
  end

  def update_invalid_preview_photos(invalid_preview_photos, opts \\ [active: false]) do
    photo_ids = invalid_preview_photos |> Enum.map(& &1.id)

    from(p in Photo, where: p.id in ^photo_ids, update: [set: ^opts])
    |> Repo.update_all([])
  end

  defdelegate path_to_url(path), to: PhotoStorage

  def initialize_resumable(name, content_type) do
    with {:ok, %{status: 200} = response} <-
           PhotoStorage.initiate_resumable(
             name,
             content_type,
             TodoplaceWeb.Endpoint.url()
           ),
         "" <> location <- Tesla.get_header(response, "location") do
      {:ok, location}
    else
      {:error, _} = error -> error
      error -> {:error, error}
    end
  end
end
