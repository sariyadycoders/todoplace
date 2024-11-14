defmodule Todoplace.Galleries.GalleryProduct do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  use StructAccess
  alias Todoplace.Category
  alias Todoplace.Galleries.{Photo, Gallery}

  schema "gallery_products" do
    field :sell_product_enabled, :boolean, default: true
    field :product_preview_enabled, :boolean, default: true
    belongs_to(:category, Category)
    belongs_to(:preview_photo, Photo)
    belongs_to(:gallery, Gallery)

    timestamps()
  end

  def changeset(%__MODULE__{} = gallery_product, attrs \\ %{}) do
    gallery_product
    |> cast(attrs, [
      :preview_photo_id,
      :category_id,
      :sell_product_enabled,
      :product_preview_enabled
    ])
  end
end
