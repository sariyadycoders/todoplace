defmodule Todoplace.Galleries.GalleryClient do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Todoplace.{Galleries.Gallery, Cart.Order}

  schema "gallery_clients" do
    field :email, :string
    field :stripe_customer_id, :string

    belongs_to(:gallery, Gallery)
    has_many(:orders, Order)

    timestamps(type: :utc_datetime)
  end

  def changeset(gallery_client, attrs \\ %{}) do
    gallery_client
    |> cast(attrs, [:email, :gallery_id, :stripe_customer_id])
    |> validate_required([:email, :gallery_id])
    |> validate_email_format(:email)
    |> unique_constraint([:email, :gallery_id])
    |> foreign_key_constraint(:gallery_id)
  end

  defp validate_email_format(changeset, email) do
    changeset
    |> validate_format(email, Todoplace.Accounts.User.email_regex(), message: "is invalid")
    |> validate_length(email, max: 160)
    |> update_change(:email, &String.downcase/1)
  end
end
