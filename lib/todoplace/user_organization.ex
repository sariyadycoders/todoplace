defmodule Todoplace.UserOrganization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "users_organizations" do
    field :role, Ecto.Enum, values: [:admin, :member], null: false
    field :status, :string
    field :last_visited_page, :string
    field :org_status, Ecto.Enum, values: [:active, :inactive, :deleted], default: :active

    belongs_to(:organization, Todoplace.Organization)
    belongs_to(:user, Todoplace.Accounts.User)

    timestamps()
  end

  @doc false
  def changeset(user_organization, attrs) do
    user_organization
    |> cast(attrs, [:user_id, :organization_id, :role, :status, :last_visited_page])
    |> validate_required([:user_id, :organization_id, :role])
    |> validate_inclusion(:role, [:admin, :member])
    |> validate_inclusion(:org_status, [:active, :inactive, :deleted])
    |> unique_constraint([:user_id, :organization_id])
  end
end
