defmodule Todoplace.Galleries.GalleryDigitalPricing do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  import Money.Sigils

  alias Todoplace.{Package, Galleries.Gallery}

  schema "gallery_digital_pricing" do
    field :download_each_price, Money.Ecto.Map.Type
    field :download_count, :integer
    field :print_credits, Money.Ecto.Map.Type, default: ~M[0]USD
    field :currency, :string, virtual: true
    field :buy_all, Money.Ecto.Map.Type
    field :email_list, {:array, :string}

    belongs_to(:gallery, Gallery)

    timestamps(type: :utc_datetime)
  end

  @create_attrs [
    :download_each_price,
    :download_count,
    :print_credits,
    :buy_all,
    :email_list,
    :gallery_id
  ]
  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @create_attrs)
    |> validate_required(~w[download_count download_each_price email_list gallery_id]a)
    |> foreign_key_constraint(:gallery_id)
    |> validate_number(:download_count, greater_than_or_equal_to: 0)
    |> then(fn changeset ->
      if Map.get(attrs, "status") !== :unlimited do
        changeset
        |> Package.validate_money(:download_each_price,
          greater_than: 200,
          message: "must be greater than two"
        )
      else
        changeset
      end
    end)
    |> Package.validate_money(:print_credits,
      greater_than_or_equal_to: 0,
      message: "must be equal to or less than total price"
    )
  end
end
