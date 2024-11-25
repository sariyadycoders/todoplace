defmodule Todoplace.AuthMethod do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:name, :string, autogenerate: false}
  schema "auth_methods" do
    timestamps()
  end

  @doc false
  def changeset(auth_method, attrs) do
    auth_method
    |> cast(attrs, [:name])
    |> validate_required([:name])
    # Enforce valid values
    |> validate_inclusion(:name, ["google", "email", "facebook"])
  end
end
