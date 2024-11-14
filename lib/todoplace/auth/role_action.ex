defmodule Todoplace.Roles.RoleAction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "role_actions" do
    field :role_id, :string
    field :action_id, :string
    field :permission_id, :string

    timestamps()
  end

  @doc false
  def changeset(role_action, attrs) do
    role_action
    |> cast(attrs, [:role_id, :action_id, :permission_id])
    |> validate_required([:role_id, :action_id, :permission_id])
    |> unique_constraint(:role_id, name: :role_actions_role_id_action_id_permission_id_index)
  end
end