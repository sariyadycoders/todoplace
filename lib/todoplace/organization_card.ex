defmodule Todoplace.OrganizationCard do
  @moduledoc false
  use Ecto.Schema
  alias Todoplace.{Card, Organization, OrganizationCard, Cart.Order, Repo}

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2, where: 3]

  schema "organization_cards" do
    field :status, Ecto.Enum, values: [:active, :viewed, :inactive]
    belongs_to(:organization, Organization)
    belongs_to(:card, Card)

    embeds_one :data, Data do
      belongs_to(:order, Todoplace.Cart.Order)
    end

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization_card \\ %__MODULE__{}, attrs) do
    organization_card
    |> cast(attrs, [:status, :card_id, :organization_id])
    |> cast_embed(:data, with: &data_changeset/2)
    |> validate_required([:card_id, :status])
  end

  def data_changeset(data, attrs) do
    data
    |> cast(attrs, [:order_id])
  end

  def for_new_changeset() do
    for %{concise_name: concise_name, id: id} <- Repo.all(Card),
        concise_name != "proofing-album-order" do
      %{
        card_id: id,
        status: "active"
      }
    end
  end

  @concise_name "proofing-album-order"
  def insert_for_proofing_order(%{album_id: nil}), do: {:ok, ""}

  def insert_for_proofing_order(%{id: order_id}) do
    organization_id =
      from(order in Order,
        join: gallery in assoc(order, :gallery),
        join: job in assoc(gallery, :job),
        join: client in assoc(job, :client),
        join: org in assoc(client, :organization),
        select: org.id,
        limit: 1,
        where: order.id == ^order_id
      )
      |> Repo.one!()

    card = Repo.get_by(Card, concise_name: @concise_name)

    Repo.insert(
      changeset(%__MODULE__{}, %{
        status: "active",
        card_id: card.id,
        organization_id: organization_id,
        data: %{order_id: order_id}
      })
    )
  end

  def list(organization_id) when is_integer(organization_id) do
    admin_panel_cards =
      from(org_card in OrganizationCard,
        where: is_nil(org_card.organization_id),
        preload: [:card]
      )
      |> Repo.all()

    # Check if is_nil(organization_id) cards from admin panel
    # are in the organization_cards table if not
    # add them so the user can dismiss the cards
    Enum.each(admin_panel_cards, fn %{card_id: card_id} ->
      if org_has_card?(organization_id, card_id) |> is_nil() do
        Repo.insert(
          changeset(%__MODULE__{}, %{
            status: "active",
            card_id: card_id,
            organization_id: organization_id
          })
        )
      end
    end)

    all_active_org_cards(organization_id)
    |> where(
      [org_card],
      org_card.status != :inactive
    )
    |> Repo.all()
  end

  def viewed!(organization_card_id) when is_integer(organization_card_id),
    do: update!(organization_card_id, :viewed)

  def inactive!(organization_card_id) when is_integer(organization_card_id),
    do: update!(organization_card_id, :inactive)

  def get_org_stripe_card(organization_id) do
    from(org_card in OrganizationCard,
      join: card in assoc(org_card, :card),
      where:
        org_card.organization_id == ^organization_id and
          card.concise_name == "set-up-stripe",
      preload: [:card]
    )
    |> Repo.one()
  end

  defp update!(organization_card_id, status) do
    __MODULE__
    |> Repo.get(organization_card_id)
    |> changeset(%{status: status})
    |> Repo.update!()
  end

  defp org_has_card?(organization_id, card_id) do
    all_active_org_cards(organization_id)
    |> where(
      [org_card],
      org_card.card_id ==
        ^card_id
    )
    |> Repo.one()
  end

  defp all_active_org_cards(organization_id) do
    from(org_card in OrganizationCard,
      where: org_card.organization_id == ^organization_id,
      preload: [:card]
    )
  end
end
