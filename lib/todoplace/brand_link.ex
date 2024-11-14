defmodule Todoplace.BrandLink do
  @moduledoc "a public image embedded in the profile json"
  use Ecto.Schema
  import Ecto.Changeset

  schema "brand_links" do
    field :title, :string
    field :link_id, :string
    field :link, :string
    field :active?, :boolean, default: false
    field :use_publicly?, :boolean, default: false
    field :show_on_profile?, :boolean, default: false

    belongs_to :organization, Todoplace.Organization
  end

  def changeset(%__MODULE__{} = brand_link, attrs) do
    cast(brand_link, attrs, [
      :title,
      :link,
      :link_id,
      :active?,
      :use_publicly?,
      :show_on_profile?,
      :organization_id
    ])
    |> validate_required([:title, :link, :organization_id, :link_id])
    |> then(&maybe_update_brand_link(&1))
    |> validate_change(
      :link,
      &for(e <- Todoplace.Profiles.Profile.url_validation_errors(&2), do: {&1, e})
    )
  end

  def update_changeset(%__MODULE__{} = brand_link, attrs \\ %{}) do
    cast(brand_link, attrs, [
      :title,
      :link,
      :link_id,
      :active?,
      :use_publicly?,
      :show_on_profile?
    ])
    |> validate_required([:title, :link, :link_id])
    |> validate_length(:title, max: 50)
    |> then(&maybe_update_brand_link(&1))
    |> validate_change(
      :link,
      &for(e <- Todoplace.Profiles.Profile.url_validation_errors(&2), do: {&1, e})
    )
  end

  def brand_link_changeset(brand_link, attrs) do
    brand_link
    |> cast(attrs, [:link])
    |> then(&maybe_update_brand_link(&1))
    |> validate_change(
      :link,
      &for(e <- Todoplace.Profiles.Profile.url_validation_errors(&2), do: {&1, e})
    )
  end

  defp maybe_update_brand_link(changeset) do
    url = get_field(changeset, :link)

    link =
      if url do
        case URI.parse(url) do
          %{scheme: nil} ->
            "https://" <> url

          _ ->
            url
        end
      else
        url
      end

    changeset
    |> put_change(:link, link)
  end

  @type t :: %__MODULE__{
          title: String.t(),
          link_id: String.t(),
          link: String.t(),
          active?: boolean(),
          use_publicly?: boolean(),
          show_on_profile?: boolean(),
          organization_id: integer()
        }
end
