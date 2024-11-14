defmodule Todoplace.InviteToken do
  use Ecto.Schema
  import Ecto.Changeset
  alias Todoplace.Repo
  alias Todoplace.InviteToken
  alias Todoplace.Organization

  schema "invite_tokens" do
    field :token, :string
    field :email, :string
    field :expires_at, :naive_datetime
    field :used, :boolean, default: false
    belongs_to :organization, Organization

    timestamps()
  end

  @doc false
  def changeset(invite_token, attrs) do
    invite_token
    |> cast(attrs, [:token, :email, :organization_id, :expires_at, :used])
    |> validate_required([:token, :email, :organization_id, :expires_at])
    |> unique_constraint(:token)
  end

  @doc """
  Generate a new invite token with a 1-hour expiration.
  """
  def generate_invite_token(email, organization_id) do
    token = :crypto.strong_rand_bytes(16) |> Base.encode64()
    expires_at = NaiveDateTime.add(NaiveDateTime.utc_now(), 3600, :second) # 1 hour expiration

    %InviteToken{}
    |> changeset(%{
      token: token,
      email: email,
      organization_id: organization_id,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  def validate_invite_token(token) do
    now = NaiveDateTime.utc_now() # Compute the current time outside the guard

    case Repo.get_by(InviteToken, token: token) |> Repo.preload(:organization) do
      %InviteToken{used: true} ->
        {:error, :already_used}

      %InviteToken{expires_at: expires_at} when expires_at < now ->
        {:error, :expired}

      %InviteToken{} = invite_token ->
        {:ok, invite_token}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Mark an invite token as used.
  """
  def mark_as_used(token) do
    Repo.get_by(InviteToken, token: token)
    |> case do
      %InviteToken{} = invite_token ->
        invite_token
        |> changeset(%{used: true})
        |> Repo.update()
        |> case do
          {:ok, _updated_invite_token} -> {:ok, :used}
          {:error, _reason} -> {:error, :update_failed}
        end

      nil ->
        {:error, :not_found}
    end
  end


  def get_by_token(token) do
    case Repo.get_by(InviteToken, token: token, used: false) do
      nil -> :error
      invite_token -> {:ok, invite_token}
    end
  end

end
