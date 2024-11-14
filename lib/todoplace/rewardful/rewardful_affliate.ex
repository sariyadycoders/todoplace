defmodule Todoplace.Rewardful do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias Ecto.Changeset
  alias Todoplace.Accounts.User

  schema "rewardful_affiliates" do
    field :affiliate_id, :string
    field :affiliate_token, :string

    belongs_to(:user, User)

    timestamps()
  end

  @spec changeset(map(), map()) :: Changeset.t()
  def changeset(rewardful_affiliate \\ %__MODULE__{}, attrs) do
    rewardful_affiliate
    |> cast(attrs, [:affiliate_id, :affiliate_token, :user_id])
    |> validate_required([:affiliate_id, :affiliate_token])
  end

  @type t :: %__MODULE__{
          affiliate_id: String.t() | nil,
          affiliate_token: String.t() | nil
        }
end
