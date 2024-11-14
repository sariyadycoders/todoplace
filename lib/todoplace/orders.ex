defmodule Todoplace.Orders do
  @moduledoc "context module for working with checked out carts"
  alias Todoplace.{
    Cart,
    Cart.Digital,
    Cart.Order,
    Cart.OrderNumber,
    Galleries,
    Galleries.Gallery,
    Galleries.Photo,
    Intents,
    Invoices.Invoice,
    Repo
  }

  import Todoplace.Orders.Confirmations, only: [send_zapier_notification: 2]

  import Ecto.Query, only: [from: 2, preload: 2]
  import Ecto.Changeset

  def all(gallery_id) do
    photo_query = from(photo in Photo, select: %{photo | watermarked: false})

    from(order in orders(),
      where: order.gallery_id == ^gallery_id,
      preload: [
        :package,
        :album,
        :intent,
        :canceled_intents,
        digitals: [photo: ^photo_query],
        products: :whcc_product
      ],
      order_by: [desc: order.placed_at]
    )
    |> Repo.all()
  end

  def find_all_by_pagination(user: user, filters: opts) do
    photo_query = from(photo in Photo, select: %{photo | watermarked: false})

    from(order in orders(),
      join: gallery in assoc(order, :gallery),
      join: job in assoc(gallery, :job),
      join: client in assoc(job, :client),
      join: organization in assoc(client, :organization),
      join: user in assoc(organization, :user),
      where: user.id == ^user.id,
      preload: [
        :intent,
        gallery: [job: [:client]],
        digitals: [photo: ^photo_query],
        products: :whcc_product
      ]
    )
    |> apply_date_filters(opts[:start_date], opts[:end_date])
    |> apply_search_filter(opts[:search_phrase])
  end

  def normalize_dates(start_date, end_date) do
    start_datetime =
      Date.from_iso8601!(start_date)
      |> NaiveDateTime.new(~T[00:00:00])
      |> elem(1)
      |> DateTime.from_naive!("Etc/UTC")

    end_datetime =
      Date.from_iso8601!(end_date)
      |> NaiveDateTime.new(~T[23:59:59.999999])
      |> elem(1)
      |> DateTime.from_naive!("Etc/UTC")

    {start_datetime, end_datetime}
  end

  def gallery_client_orders(gallery_id, gallery_client_id) do
    photo_query = from(photo in Photo, select: %{photo | watermarked: false})

    from(order in orders(),
      where: order.gallery_id == ^gallery_id and order.gallery_client_id == ^gallery_client_id,
      preload: [
        :package,
        :intent,
        :canceled_intents,
        digitals: [photo: ^photo_query],
        products: :whcc_product
      ],
      order_by: [desc: order.placed_at]
    )
    |> Repo.all()
  end

  defp apply_date_filters(query, start_date, end_date) do
    if is_nil(start_date) or is_nil(end_date) do
      query
    else
      {start_datetime, end_datetime} = normalize_dates(start_date, end_date)

      from(order in query,
        where: order.updated_at >= ^start_datetime,
        where: order.updated_at <= ^end_datetime
      )
    end
  end

  defp apply_search_filter(query, search_phrase) do
    if is_nil(search_phrase) or search_phrase == "" do
      query
    else
      from([order, gallery, job, client] in query,
        where:
          ilike(client.name, ^"%#{search_phrase}%") or
            ilike(job.job_name, ^"%#{search_phrase}%") or
            ilike(fragment("?->>'amount'", order.bundle_price), ^"%#{search_phrase}%") or
            ilike(
              fragment("to_char(?, 'YYYY-MM-DD HH24:MI:SS')", order.updated_at),
              ^"%#{search_phrase}%"
            )
      )
    end
  end

  defp topic(order), do: "order:#{Order.number(order)}"

  def subscribe(order), do: Phoenix.PubSub.subscribe(Todoplace.PubSub, topic(order))

  def broadcast(order, message),
    do: Phoenix.PubSub.broadcast(Todoplace.PubSub, topic(order), message)

  def has_download?(%Order{bundle_price: bundle_price, digitals: digitals}),
    do: bundle_price != nil || digitals != []

  def client_paid?(%{id: order_id}),
    do: Repo.exists?(from(orders in client_paid_query(), where: orders.id == ^order_id))

  def photographer_paid?(%{id: order_id}),
    do:
      not Repo.exists?(
        from(invoice in Invoice, where: invoice.order_id == ^order_id and invoice.status != :paid)
      )

  def client_paid_query, do: client_paid_query(orders())

  def client_paid_query(source),
    do:
      from(orders in source,
        left_join: intents in subquery(Intents.unpaid_query()),
        on: intents.order_id == orders.id,
        where: is_nil(intents.id)
      )

  def orders(), do: from(orders in Order, where: not is_nil(orders.placed_at))

  def get_whcc_orders() do
    from(order in Order,
      where: not is_nil(order.placed_at) and not is_nil(order.whcc_order),
      preload: [:gallery_client, gallery: [:organization]],
      order_by: [desc: order.placed_at]
    )
    |> Repo.all()
  end

  def placed_orders_count(%Gallery{id: id}),
    do:
      from(o in Order,
        select: count(o.id),
        where: o.gallery_id == ^id and not is_nil(o.placed_at)
      )
      |> Repo.one()

  def get!(gallery, order_number) do
    watermarked_query = Todoplace.Photos.watermarked_query()

    gallery
    |> placed_order_query(order_number)
    |> preload([
      :intent,
      :canceled_intents,
      [
        :album,
        gallery: [:organization, :package],
        products: :whcc_product,
        digitals: [photo: ^watermarked_query]
      ]
    ])
    |> Repo.one!()
  end

  def get_purchased_photo!(gallery, photo_id) do
    if can_download_all?(gallery) do
      from(photo in Photo, where: photo.gallery_id == ^gallery.id and photo.id == ^photo_id)
      |> Repo.one!()
    else
      from(digital in Digital,
        join: order in subquery(client_paid_query()),
        on: order.id == digital.order_id,
        join: photo in assoc(digital, :photo),
        where: order.gallery_id == ^gallery.id and digital.photo_id == ^photo_id,
        select: photo
      )
      |> Repo.one!()
    end
  end

  def update_digital_photo(gallery_id, old_photo_id, new_photo_id) do
    Cart.digital_purchased_query(gallery_id, [old_photo_id])
    |> Repo.one!()
    |> Repo.preload(:order)
    |> change(photo_id: new_photo_id)
    |> Repo.update()
  end

  def get_all_purchased_photos_in_album(gallery, album_id) do
    if can_download_all?(gallery) do
      from(photo in Photo,
        where: photo.gallery_id == ^gallery.id and photo.album_id == ^album_id,
        where: photo.active == true
      )
      |> Repo.all()
    else
      from(digital in Digital,
        join: order in subquery(client_paid_query()),
        on: order.id == digital.order_id,
        join: photo in assoc(digital, :photo),
        where: order.gallery_id == ^gallery.id,
        where: photo.album_id == ^album_id,
        where: photo.active == true,
        select: photo
      )
      |> Repo.all()
    end
  end

  def get_all_photos!(%{client_link_hash: gallery_hash} = gallery) do
    if can_download_all?(gallery) do
      %{
        organization: get_organization!(gallery_hash),
        photos:
          from(photo in Photo,
            where: photo.gallery_id == ^gallery.id,
            where: photo.active == true
          )
          |> some!()
      }
    else
      raise Ecto.NoResultsError, queryable: Gallery
    end
  end

  def get_all_photos(gallery) do
    {:ok, get_all_photos!(gallery)}
  rescue
    e in Ecto.NoResultsError -> {:error, e}
  end

  @doc "stores processing info in order it finds"
  def update_whcc_order(%{entry_id: entry_id} = payload, helpers) do
    case from(order in Order,
           where: fragment("? ->> 'entry_id' = ?", order.whcc_order, ^entry_id),
           preload: [products: :whcc_product]
         )
         |> Repo.one() do
      nil ->
        {:error, "order not found"}

      order ->
        order
        |> Order.whcc_order_changeset(payload)
        |> Repo.update()
        |> case do
          {:ok, updated_order} ->
            maybe_send_shipping_notification(payload, updated_order, helpers)

            updated_order
            |> Repo.preload(gallery: [job: [client: [organization: [:user]]]])
            |> send_zapier_notification("updated_order")

            {:ok, updated_order}

          error ->
            error
        end
    end
  end

  defp maybe_send_shipping_notification(
         %Todoplace.WHCC.Webhooks.Event{event: "Shipped"} = event,
         order,
         helpers
       ) do
    Todoplace.Notifiers.ClientNotifier.deliver_shipping_notification(event, order, helpers)
    Todoplace.Notifiers.UserNotifier.deliver_shipping_notification(event, order, helpers)
  end

  defp maybe_send_shipping_notification(_payload, _order, _helpers), do: nil

  def can_download_all?(%Gallery{} = gallery) do
    Galleries.do_not_charge_for_download?(gallery) || bundle_purchased?(gallery)
  end

  def bundle_purchased?(%{id: gallery_id}) do
    from(order in client_paid_query(),
      where: order.gallery_id == ^gallery_id and not is_nil(order.bundle_price)
    )
    |> Repo.exists?()
  end

  defdelegate handle_session(order_number, stripe_session_id),
    to: __MODULE__.Confirmations

  defdelegate handle_session(session), to: __MODULE__.Confirmations
  defdelegate handle_invoice(invoice), to: __MODULE__.Confirmations
  defdelegate handle_intent(intent), to: __MODULE__.Confirmations
  defdelegate canceled?(order), to: Order
  defdelegate number(order), to: Order

  def get_order_photos(%Order{bundle_price: %Money{}} = order) do
    from(photo in Photo,
      where: photo.gallery_id == ^order.gallery_id,
      where: photo.active == true,
      order_by: [asc: photo.inserted_at]
    )
  end

  def get_order_photos(%Order{id: order_id}) do
    from(order in Order,
      join: digital in assoc(order, :digitals),
      join: photo in assoc(digital, :photo),
      where: order.id == ^order_id,
      where: photo.active == true,
      order_by: [asc: photo.inserted_at],
      where: photo.active == true,
      select: photo
    )
  end

  defp some!(query),
    do:
      query
      |> Repo.all()
      |> (case do
            [] -> raise Ecto.NoResultsError, queryable: query
            some -> some
          end)

  defp placed_order_query(%{client_link_hash: gallery_hash}, order_number) do
    order_id = OrderNumber.from_number(order_number)

    from(order in orders(),
      as: :order,
      join: gallery in assoc(order, :gallery),
      as: :gallery,
      where: gallery.client_link_hash == ^gallery_hash and order.id == ^order_id
    )
  end

  defp get_organization!(gallery_hash) do
    from(gallery in Gallery,
      join: org in assoc(gallery, :organization),
      where: gallery.client_link_hash == ^gallery_hash,
      select: org
    )
    |> Repo.one!()
  end

  def get_all_proofing_album_orders_query(organization_id) do
    from(order in get_all_orders_query(organization_id),
      join: album in assoc(order, :album),
      where: album.is_proofing == true and not is_nil(order.placed_at),
      preload: [:album, gallery: [job: [:client]]]
    )
  end

  def has_proofing_album_orders?(gallery) do
    Repo.exists?(
      from(order in get_all_proofing_album_orders_query(gallery.organization.id),
        where: order.gallery_id == ^gallery.id and order.inserted_at > ago(7, "day")
      )
    )
  end

  def get_all_orders_query(organization_id) do
    from(order in Todoplace.Cart.Order,
      join: gallery in assoc(order, :gallery),
      join: job in assoc(gallery, :job),
      join: client in assoc(job, :client),
      join: organization in assoc(client, :organization),
      where: organization.id == ^organization_id
    )
  end

  @filtered_days 7
  def get_all_proofing_album_orders(organization_id) do
    from(order in get_all_proofing_album_orders_query(organization_id),
      where: order.inserted_at > ago(@filtered_days, "day")
    )
    |> Repo.all()
  end

  def get_proofing_order(album_id, organization_id) do
    from(order in get_all_proofing_album_orders_query(organization_id),
      where: order.album_id == ^album_id,
      preload: [gallery: [job: [:client]]]
    )
    |> Repo.all()
  end

  def get_proofing_order_photos(album_id, organization_id) do
    photo_query = from(photo in Photo, select: %{photo | watermarked: false})

    from(order in get_all_proofing_album_orders_query(organization_id),
      where: order.album_id == ^album_id,
      preload: [
        digitals: [photo: ^photo_query]
      ],
      order_by: [desc: order.placed_at]
    )
    |> Repo.all()
  end

  def get_order_from_order_number(order_number) do
    from(order in Order,
      preload: [gallery: :job],
      where: order.number == ^order_number
    )
    |> Repo.one()
  end

  @doc """
  Retrieves an order by its ID.

  This function queries the database to retrieve an order based on the provided order ID.
  It preloads associated data, including the gallery and job, for more comprehensive order information.

  ## Parameters

      - `id`: The unique identifier (ID) of the order to retrieve.

  ## Returns

      - `%Order{}`: A struct representing the retrieved order with associated data, including the gallery and job.

  ## Examples

      ```elixir
      order_id = 123
      order = MyApp.Orders.get_order(order_id)

      # Accessing order details:
      # order.gallery - The associated gallery for the order
      # order.job - The associated job for the order
  """
  def get_order(id) do
    photo_query = from(photo in Photo, select: %{photo | watermarked: false})

    from(order in Order,
      preload: [
        :intent,
        gallery: [job: [:client]],
        digitals: [photo: ^photo_query],
        products: :whcc_product
      ],
      where: order.id == ^id
    )
    |> Repo.one()
  end
end
