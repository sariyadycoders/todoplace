defmodule Todoplace.Shipment.DasType do
  @moduledoc "area surcharge types for different zipcodes"
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Todoplace.Shipment.{DasType, Zipcode}
  alias Todoplace.Repo

  schema "shipment_das_types" do
    field :mail_cost, Money.Ecto.Amount.Type
    field :parcel_cost, Money.Ecto.Amount.Type
    field :name, :string

    timestamps()
  end

  @fields [:name, :mail_cost, :parcel_cost]
  @doc false
  def changeset(das_cost, attrs \\ %{}) do
    das_cost
    |> cast(attrs, @fields)
    |> validate_required(@fields)
  end

  def all(), do: Repo.all(__MODULE__ |> order_by([d], d.inserted_at))

  def get_by_zipcode(zipcode) do
    from(dt in DasType,
      join: zipcode in Zipcode,
      on: dt.id == zipcode.das_type_id,
      where: zipcode.zipcode == ^zipcode,
      limit: 1
    )
    |> Repo.one()
  end
end
