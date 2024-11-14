defmodule Todoplace.GalleryProducts do
  @moduledoc false

  import Ecto.Query, warn: false
  import Todoplace.Repo.CustomMacros
  alias Todoplace.{Repo, Galleries, Subscriptions, Product, Galleries.GalleryProduct}

  def upsert_gallery_product(gallery_product, attr) do
    gallery_product
    |> GalleryProduct.changeset(attr)
    |> Repo.insert_or_update()
  end

  def get(fields) do
    from(gp in GalleryProduct,
      left_join: preview_photo in subquery(Todoplace.Photos.watermarked_query()),
      on: gp.preview_photo_id == preview_photo.id,
      select_merge: %{preview_photo: preview_photo},
      where: ^fields,
      preload: :category
    )
    |> Repo.one()
  end

  def toggle_sell_product_enabled(product) do
    product
    |> GalleryProduct.changeset(%{sell_product_enabled: !product.sell_product_enabled})
    |> Repo.update!()
  end

  def toggle_product_preview_enabled(product) do
    product
    |> GalleryProduct.changeset(%{product_preview_enabled: !product.product_preview_enabled})
    |> Repo.update!()
  end

  def editor_type(%GalleryProduct{category_id: category_id}) do
    editor_types = %{
      "simpleEditor" => :simple,
      "cardEditor" => :card,
      "albumEditor" => :album
    }

    type =
      from(product in Todoplace.Product,
        join: category in assoc(product, :category),
        where: category.id == ^category_id,
        select: product.api ~> "editorType",
        distinct: true
      )
      |> Repo.one!()

    Map.get(editor_types, type)
  end

  @doc """
  Get all the gallery products that are ready for review
  """
  def get_gallery_products(%{id: id, use_global: use_global}, opts) do
    if maybe_query_products_with_active_payment_method(id) do
      id
      |> gallery_products_query(opts)
      |> Repo.all()
      |> Enum.map(&Todoplace.WHCC.update_markup(&1, %{use_global: use_global}))
    else
      []
    end
  end

  defp gallery_products_query(gallery_id, :coming_soon_false) do
    gallery_products_query(gallery_id, :with_or_without_previews)
    |> where([preview_photo: preview_photo], not is_nil(preview_photo.id))
    |> where([category: category], not category.coming_soon)
    |> where(sell_product_enabled: true)
  end

  defp gallery_products_query(gallery_id, :with_or_without_previews) do
    from(product in GalleryProduct,
      join: gallery in assoc(product, :gallery),
      join: photographer in assoc(gallery, :photographer),
      inner_join: category in assoc(product, :category),
      as: :category,
      left_join: gs_gallery_product in assoc(category, :gs_gallery_products),
      on: gs_gallery_product.organization_id == photographer.organization_id,
      left_join: preview_photo in subquery(Todoplace.Photos.watermarked_query()),
      on: preview_photo.id == product.preview_photo_id,
      as: :preview_photo,
      where:
        product.gallery_id == ^gallery_id and not category.hidden and is_nil(category.deleted_at),
      where: photographer.onboarding ~>> "state" != ^Todoplace.Onboardings.non_us_state(),
      preload: [
        :gallery,
        category: {category, [:products, gs_gallery_products: gs_gallery_product]}
      ],
      select_merge: %{preview_photo: preview_photo},
      order_by: category.position
    )
  end

  def remove_photo_preview(photo_ids) do
    from(p in GalleryProduct,
      where: p.preview_photo_id in ^photo_ids,
      update: [set: [preview_photo_id: nil]]
    )
  end

  @doc """
  Product sourcing and creation.
  """
  def get_or_create_gallery_product(gallery_id, category_id) do
    get_gallery_product(gallery_id, category_id)
    |> case do
      nil ->
        %GalleryProduct{
          gallery_id: gallery_id,
          category_id: category_id
        }
        |> Repo.insert!()

      product ->
        product
    end
    |> Repo.preload([:preview_photo, category: :products])
  end

  @doc """
  Product search.
  """
  def get_gallery_product(gallery_id, category_id) do
    GalleryProduct
    |> Repo.get_by(gallery_id: gallery_id, category_id: category_id)
  end

  @doc """
  Gets WHCC products with size params.
  """

  def get_whcc_products(category_id) do
    sizes =
      from(product in Product,
        join:
          attributes in jsonb_path_query_args(
            product.attribute_categories,
            "$[*] \? (@._id == $id).attributes[*]",
            ^%{id: "size"}
          ),
        on: true,
        group_by: product.id,
        select: %{
          product_id: product.id,
          sizes:
            jsonb_agg(jsonb_object(["name", attributes ~>> "name", "id", attributes ~>> "id"]))
        }
      )

    from(product in with_cte(Product, "sizes", as: ^sizes),
      where: product.category_id == ^category_id and is_nil(product.deleted_at),
      inner_join: sizes in "sizes",
      on: sizes.product_id == product.id,
      order_by: [asc: product.position],
      select: merge(product, %{sizes: sizes.sizes})
    )
    |> Repo.all()
  end

  @doc """
  Gets WHCC product by WHCC product id.
  """
  def get_whcc_product(whcc_id) do
    Repo.get_by(Product, whcc_id: whcc_id)
  end

  def get_whcc_product_category(whcc_id) do
    whcc_id
    |> get_whcc_product()
    |> Repo.preload(:category)
    |> then(& &1.category)
  end

  defp maybe_query_products_with_active_payment_method(gallery_id) do
    Galleries.get_gallery!(gallery_id)
    |> Galleries.gallery_photographer()
    |> Subscriptions.subscription_payment_method?()
  end
end
