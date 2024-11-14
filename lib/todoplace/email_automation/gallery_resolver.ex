defmodule Todoplace.EmailPresets.GalleryResolver do
  @moduledoc "resolves gallery mustache variables"

  defstruct [:gallery, :order, :album, :helpers]
  alias Todoplace.{Galleries.Gallery, Galleries.Album, Cart.Order, Pack}

  def new({%Gallery{} = gallery}, helpers),
    do: %__MODULE__{
      gallery: preload_gallery(gallery),
      helpers: helpers
    }

  def new({%Gallery{} = gallery, %Order{} = order}, helpers),
    do: %__MODULE__{
      gallery: preload_gallery(gallery),
      order: order,
      helpers: helpers
    }

  def new({%Gallery{} = gallery, %Album{} = album}, helpers),
    do: %__MODULE__{
      gallery: preload_gallery(gallery),
      album: album,
      helpers: helpers
    }

  defp preload_gallery(gallery),
    do:
      Todoplace.Repo.preload(gallery,
        job: [client: [organization: :user]]
      )

  defp gallery(%__MODULE__{gallery: gallery}), do: gallery

  defp order(%__MODULE__{order: order}), do: order

  defp album(%__MODULE__{album: album}), do: album

  defp job(%__MODULE__{gallery: gallery}),
    do: gallery |> Todoplace.Repo.preload(:job) |> Map.get(:job)

  defp client(%__MODULE__{} = resolver),
    do: resolver |> job() |> Todoplace.Repo.preload(:client) |> Map.get(:client)

  defp organization(%__MODULE__{} = resolver),
    do: resolver |> client() |> Todoplace.Repo.preload(:organization) |> Map.get(:organization)

  defp photographer(%__MODULE__{} = resolver),
    do: resolver |> organization() |> Todoplace.Repo.preload(:user) |> Map.get(:user)

  defp strftime(%__MODULE__{helpers: helpers} = resolver, date, format) do
    resolver |> photographer() |> Map.get(:time_zone) |> helpers.strftime(date, format)
  end

  ## Generates a download link for photos in a gallery. This private function takes an instance of the current module
  ## (usually representing a gallery) and attempts to generate a download link for the photos in the gallery.
  ## It uses the `Pack.url/1` function to create the download link. If successful, it returns the download
  ## link as a string; otherwise, it returns nil.
  defp download_photos_link(%__MODULE__{gallery: gallery}) do
    case Pack.url(gallery) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp helpers(%__MODULE__{helpers: helpers}), do: helpers

  def vars,
    do: %{
      "client_first_name" => &(&1 |> client() |> Map.get(:name) |> String.split() |> hd),
      "password" => &(&1 |> gallery() |> Map.get(:password)),
      "gallery_link" =>
        &with(
          %Gallery{client_link_hash: "" <> client_link_hash} <- gallery(&1),
          do: """
          <a target="_blank" href="#{helpers(&1).gallery_url(client_link_hash)}">
            Gallery Link
          </a>
          """
        ),
      "client_gallery_order_page" =>
        &with(
          %Album{client_link_hash: "" <> client_link_hash} <- album(&1),
          do: """
          <a target="_blank" href="#{helpers(&1).album_url(client_link_hash)}/cart">
            Order Page Link
          </a>
          """
        ),
      "photography_company_s_name" => &organization(&1).name,
      "photographer_first_name" => &(&1 |> photographer() |> Todoplace.Accounts.User.first_name()),
      "gallery_name" => &(&1 |> gallery() |> Map.get(:name)),
      "download_photos" =>
        &with(
          link <- download_photos_link(&1),
          do: """
          <a target="_blank" href="#{link}">
            Download Photos Link
          </a>
          """
        ),
      "gallery_expiration_date" =>
        &with(
          %DateTime{} = expired_at <- &1 |> gallery() |> Map.get(:expired_at),
          do: strftime(&1, expired_at, "%B %-d, %Y")
        ),
      "order_first_name" =>
        &with(
          %Order{delivery_info: delivery_info} <- order(&1),
          do:
            case delivery_info do
              nil -> ""
              _ -> delivery_info |> Map.get(:name) |> String.split() |> hd()
            end
        ),
      "order_full_name" =>
        &with(
          %Order{delivery_info: delivery_info} <- order(&1),
          do:
            case delivery_info do
              nil -> ""
              _ -> delivery_info |> Map.get(:name)
            end
        ),
      "album_link" =>
        &with(
          %Album{client_link_hash: "" <> client_link_hash} <- album(&1),
          do: """
          <a target="_blank" href="#{helpers(&1).album_url(client_link_hash)}">
            Download Photos Link
          </a>
          """
        ),
      "album_password" => &(&1 |> gallery() |> Map.get(:password))
    }
end
