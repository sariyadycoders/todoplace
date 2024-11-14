defmodule Todoplace.Galleries.Album do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  alias Todoplace.Galleries.{Gallery, SessionToken, Photo}
  alias Todoplace.Cart.Order

  @session_opts [
    foreign_key: :resource_id,
    where: [resource_type: :album],
    on_delete: :delete_all
  ]

  schema "albums" do
    field(:name, :string)
    field(:position, :float)
    field(:client_link_hash, :string)
    field(:is_proofing, :boolean, default: false)
    field(:is_finals, :boolean, default: false)
    field(:show, :boolean, virtual: true, default: true)
    field(:is_client_liked, :boolean, virtual: true, default: false)
    belongs_to(:gallery, Gallery)
    belongs_to(:thumbnail_photo, Photo, on_replace: :nilify)
    has_many(:photos, Photo)
    has_many(:session_tokens, SessionToken, @session_opts)
    has_many(:orders, Order, on_delete: :nilify_all)

    timestamps(type: :utc_datetime)
  end

  @attrs [
    :name,
    :position,
    :gallery_id,
    :is_proofing,
    :is_finals,
    :client_link_hash
  ]
  @required_attrs [:name, :gallery_id]

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @attrs)
    |> validate_required(@required_attrs)
    |> validate_name()
  end

  def gallery_changeset(album \\ %__MODULE__{}, attrs) do
    album
    |> cast(attrs, @attrs)
    |> validate_required(:name)
  end

  def update_changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, @attrs)
    |> validate_required(@required_attrs)
    |> validate_name()
  end

  def password_changeset(album, attrs \\ %{}) do
    album
    |> cast(attrs, [:password])
    |> validate_required([:password])
  end

  def update_thumbnail(album, photo) do
    album |> change() |> put_assoc(:thumbnail_photo, photo)
  end

  defp topic(album), do: "album:#{album.id}"

  def subscribe(album),
    do: Phoenix.PubSub.subscribe(Todoplace.PubSub, topic(album))

  def broadcast(album, message),
    do: Phoenix.PubSub.broadcast(Todoplace.PubSub, topic(album), message)

  defp validate_name(changeset),
    do: validate_length(changeset, :name, max: 35)

  @type t :: %__MODULE__{
          client_link_hash: String.t(),
          gallery_id: integer()
        }
end
