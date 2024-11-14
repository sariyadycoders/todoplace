defmodule Todoplace.WHCC.Editor.Params do
  @moduledoc "Editor creation params builder"
  alias Todoplace.{Repo, Product, Galleries, Photos, WHCC.Editor.PhotoParams}

  def build(%Product{} = product, photo, opts) do
    product = product |> Repo.preload(:category)

    {opts, photo_opts} = split_opts(opts)

    %{gallery: %{organization: organization} = gallery} =
      photo = Repo.preload(photo, gallery: :organization)

    gallery_photos = Photos.get_related(photo, photo_opts)

    color = Todoplace.Profiles.color(organization)

    %{
      "userId" => Galleries.account_id(gallery),
      "productId" => product.whcc_id,
      "photos" => PhotoParams.from(photo, gallery_photos),
      "redirects" => redirects(opts),
      "settings" => settings(organization.name, color),
      "selections" => selections(photo, opts)
    }
    |> add_design(Keyword.get(opts, :design))
  end

  defp split_opts(opts) do
    {favorites_only, opts} = Keyword.pop(opts, :favorites_only, false)
    {album_id, opts} = Keyword.pop(opts, :album_id)

    {opts, album_id: album_id, favorites_only: favorites_only}
  end

  defp add_design(selected_params, nil), do: selected_params
  defp add_design(selected_params, id), do: Map.put(selected_params, "designId", id)

  defp selections(photo, opts) do
    selections = %{
      "photo" => %{
        "galleryId" => PhotoParams.id(photo),
        "height" => photo.height,
        "width" => photo.width,
        "x" => 0,
        "y" => 0
      }
    }

    case Keyword.get(opts, :size) do
      nil -> selections
      size -> Map.put(selections, "size", size)
    end
  end

  defp settings(name, color) do
    %{
      "client" => %{
        "vendor" => "default",
        "accentColor" => color,
        "hidePricing" => true,
        "studioName" => name,
        "markupType" => "PERCENT",
        "markupAmount" => 0,
        "disableUploads" => true
      }
    }
  end

  defp redirects(opts) do
    %{
      "complete" => %{
        "url" => Keyword.get(opts, :complete_url, ""),
        "text" => Keyword.get(opts, :complete_text, "Save Product")
      },
      "cancel" => %{
        "url" => Keyword.get(opts, :cancel_url, ""),
        "text" => Keyword.get(opts, :cancel_text, "Cancel")
      },
      "secondary" => %{
        "url" => Keyword.get(opts, :secondary_url, ""),
        "text" => Keyword.get(opts, :secondary_text, "Add and continue shopping")
      }
    }
  end
end
