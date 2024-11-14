defmodule Todoplace.Onboarding.Welcome do
  @moduledoc "context module for photographer welcome tracking"
  use Ecto.Schema

  import Ecto.Changeset

  schema "users_onboarding" do
    field(:completed_at, :utc_datetime)
    field(:group, :string)
    field(:slug, :string)

    timestamps(type: :utc_datetime)

    belongs_to :user, Todoplace.Accounts.User
  end

  @doc false
  def changeset(onboarding \\ %__MODULE__{}, attrs) do
    onboarding
    |> cast(attrs, [:completed_at, :group, :slug])
    |> validate_required([:completed_at, :group, :slug])
  end
end
