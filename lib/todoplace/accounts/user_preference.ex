defmodule Todoplace.Accounts.UserPreference do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_preferences" do
    # JSON field for flexible storage
    field :settings, :map, default: %{}

    belongs_to :user, Todoplace.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(user_preference, attrs) do
    user_preference
    |> cast(attrs, [:settings, :user_id])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end
end
