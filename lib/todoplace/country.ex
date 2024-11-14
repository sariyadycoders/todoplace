defmodule Todoplace.Country do
  @moduledoc "countries for business address"
  use Ecto.Schema
  alias Todoplace.Repo

  @primary_key false
  schema "countries" do
    field :code, :string
    field :name, :string
  end

  def all(), do: Repo.all(__MODULE__)
end
