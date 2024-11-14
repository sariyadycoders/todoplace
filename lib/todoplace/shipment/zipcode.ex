defmodule Todoplace.Shipment.Zipcode do
  @moduledoc "zipcodes for calculating shipping surcharge"
  use Ecto.Schema
  alias Todoplace.Repo

  schema "shipment_zipcodes" do
    field :zipcode, :string
    belongs_to :das_type, Todoplace.Shipment.DasType
  end

  def all(), do: Repo.all(__MODULE__)
end
