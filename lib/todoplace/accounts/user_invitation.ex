defmodule Todoplace.Accounts.UserInvitation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_invitations" do
    field :token, :string
    belongs_to(:organization, Todoplace.Organization)
    field :user_email, :string
    field :used, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(user_invitation, attrs) do
    user_invitation
    |> cast(attrs, [:token, :organization_id, :user_email, :used])
    |> validate_required([:token, :organization_id, :user_email, :used])
    |> unique_constraint(:token)
  end
end