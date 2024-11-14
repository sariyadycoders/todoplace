defmodule Todoplace.App do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "apps" do
    field :description, :string

    timestamps()
  end

  @doc false
  def changeset(app, attrs) do
    app
    |> cast(attrs, [:id, :description])
    |> validate_required([:id, :description])
  end
end
