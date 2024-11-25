defmodule Todoplace.Cart.Checkouts do
  @moduledoc "context module for checking out a cart"

  alias Todoplace.{
    Cart.Digital,
    Cart.Order,
    Cart.Product,
    Galleries,
    Intents,
    Payments,
    Repo,
    WHCC,
    Cart,
    OrganizationCard,
    EmailAutomationSchedules,
    Galleries.GalleryClient
  }

  alias WHCC.Editor.Export.Editor

  require Logger

  import Todoplace.Cart,
    only: [
      product_name: 1,
      product_quantity: 1,
      item_image_url: 1,
      preload_digitals: 1
    ]

  import Ecto.Multi, only: [new: 0, run: 3, merge: 2, insert: 3, update: 3, append: 2, put: 3]

  import Ecto.Query, only: [from: 2]

  @doc """
  1. order already has a session?
      1. expire session
      2. update intent
  1. contains products?
      1. create whcc order (needed for fee amount)
      2. outstanding whcc charges?
          2. client does not owe?
              1. create invoice
              2. finalize invoice
  2. client owes?
      2. create checkout session (with fee amount)
      3. insert intent
  3. client does not owe?
      1. place todoplace order
  """

  @spec check_out(integer(), map()) ::
          {:ok, map()} | {:error, any(), any(), map()}
  def check_out(order_id, opts) do
    Logger.info("Reached checkout method for #{inspect(order_id)}")

    order_id
    |> handle_previous_session()
    |> append(
      new()
      |> run(:cart, :load_cart, [order_id])
      |> run(:client_total, &client_total/2)
      |> merge(fn
        %{client_total: %Money{amount: 0}, cart: %{products: []} = cart} ->
          new()
          |> update(:order, place_order(cart))
          |> run(:insert_card, fn _repo, %{order: order} ->
            OrganizationCard.insert_for_proofing_order(order)
          end)
          |> run(:insert_orders_emails, fn _repo, %{order: order} ->
            EmailAutomationSchedules.insert_gallery_order_emails(nil, order)
          end)

        %{cart: %{products: []} = cart} ->
          create_session(cart, opts)

        %{client_total: _client_total, cart: %{products: [_ | _]} = cart} ->
          new()
          |> append(create_whcc_order(cart))
          |> merge(
            &create_session(
              cart,
              opts |> Map.merge(&1)
            )
          )
      end)
    )
    |> Repo.transaction()
  end

  def handle_previous_session(order_id) do
    new()
    |> merge(fn _ ->
      case load_previous_intent(order_id) do
        nil ->
          new()

        intent ->
          new()
          |> put(:previous_intent, intent)
          |> run(:previous_stripe_intent, &fetch_previous_stripe_intent/2)
          |> run(:expire_previous_session, &expire_previous_session/2)
          |> update(:updated_previous_intent, &update_previous_intent/1)
      end
    end)
  end

  defp load_previous_intent(order_id),
    do:
      from(intent in Intents.unresolved_for_order(order_id),
        join: order in assoc(intent, :order),
        join: gallery in assoc(order, :gallery),
        join: organization in assoc(gallery, :organization),
        preload: [order: {order, [gallery: {gallery, [organization: organization]}]}]
      )
      |> Repo.one()

  defp expire_previous_session(_repo, %{previous_stripe_intent: %{status: "canceled"} = intent}) do
    {:ok, %{payment_intent: intent}}
  end

  defp expire_previous_session(_repo, %{
         previous_intent: %{
           stripe_session_id: id,
           order: %{gallery: %{organization: %{stripe_account_id: connect_account}}}
         }
       }) do
    Payments.expire_session(id, connect_account: connect_account, expand: [:payment_intent])
    |> case do
      {:ok, %{status: "expired", payment_intent: intent} = session} ->
        {:ok, %{session | payment_intent: %{intent | status: "canceled"}}}

      error ->
        error
    end
  end

  defp update_previous_intent(%{
         previous_intent: intent,
         expire_previous_session: %{payment_intent: stripe_intent}
       }) do
    Intents.changeset(intent, stripe_intent)
  end

  def load_cart(repo, _multi, order_id) do
    from(order in Order,
      join: gallery in assoc(order, :gallery),
      join: organization in assoc(gallery, :organization),
      join: user in assoc(organization, :user),
      preload: [
        gallery: {gallery, [organization: {organization, [user: user]}]},
        products: :whcc_product
      ],
      where: order.id == ^order_id and is_nil(order.placed_at)
    )
    |> preload_digitals()
    |> repo.one()
    |> case do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  end

  defp create_whcc_order(%Order{delivery_info: delivery_info, gallery_id: gallery_id} = order) do
    shipment_details = Todoplace.Shipment.Detail.all()

    editors =
      order
      |> Todoplace.Cart.Order.lines_by_product()
      |> Enum.reduce([], &editors(&1, &2, shipment_details))

    account_id = Galleries.account_id(gallery_id)

    export =
      WHCC.editors_export(account_id, editors,
        entry_id: order |> Order.number() |> to_string(),
        address: delivery_info
      )

    Logger.info("Reached create whcc order method for #{inspect(gallery_id)}")

    new()
    |> run(:whcc_order, fn _, _ ->
      WHCC.create_order(account_id, export)
    end)
    |> update(:save_whcc_order, &Order.whcc_order_changeset(order, &1.whcc_order))
  end

  defp editors({_whcc_product, line_items}, acc, shipment_details) do
    product = Enum.find(line_items, & &1.shipping_type)
    order_attributes = WHCC.Shipping.attributes(product, shipment_details)

    acc ++ Enum.map(line_items, &Editor.new(&1.editor_id, order_attributes: order_attributes))
  end

  defp create_session(cart, opts) do
    shipping_price = Cart.total_shipping(cart)
    Logger.info("Reached create_session method for order id #{inspect(cart.id)}")

    create_session(
      cart,
      Product.total_cost(cart) |> Money.add(shipping_price),
      opts
    )
  end

  defp create_session(
         %{gallery: %{organization: %{stripe_account_id: stripe_account_id} = organization}} =
           order,
         %{amount: application_fee_cents},
         %{"success_url" => success_url, "cancel_url" => cancel_url}
       ) do
    total_cost = Order.total_cost(order)
    order_number = Order.number(order)

    # if total_cost is less than %Money{5000} then filter out affirm per their requirements
    payment_method_types =
      Payments.map_payment_opts_to_stripe_opts(organization)
      |> Enum.filter(fn method ->
        if total_cost.amount < 5000 do
          method != "affirm"
        else
          true
        end
      end)

    params = %{
      shipping_address_collection: %{
        allowed_countries: ["US"]
      },
      payment_method_types: payment_method_types,
      line_items: build_line_items(order),
      client_reference_id: "order_number_#{order_number}",
      payment_intent_data: %{
        application_fee_amount: application_fee_cents,
        capture_method: :manual
      },
      shipping_options: shipping_options(order),
      success_url: success_url,
      billing_address_collection: "auto",
      cancel_url: cancel_url
    }

    new()
    |> run(:gallery_client, fn _, _ ->
      params = build_stripe_customer_params(order)
      opts = [connect_account: stripe_account_id]
      Logger.info("Reached create session method for #{inspect(params)}")

      order
      |> Repo.preload(:gallery_client)
      |> Map.get(:gallery_client)
      |> case do
        %{stripe_customer_id: "" <> customer_id} = gallery_client ->
          {:ok, _} = Payments.update_customer(customer_id, params, opts)

          {:ok, gallery_client}

        gallery_client ->
          {:ok, %{id: id}} = Payments.create_customer(params, opts)

          gallery_client
          |> GalleryClient.changeset(%{stripe_customer_id: id})
          |> Repo.update()
      end
    end)
    |> run(:session, fn _, %{gallery_client: %{stripe_customer_id: stripe_customer_id}} ->
      Logger.info("Reached create session method for #{inspect(stripe_customer_id)}")

      Payments.create_session(
        params |> Map.put(:customer, stripe_customer_id),
        expand: [:payment_intent],
        connect_account: stripe_account_id
      )
    end)
    |> insert(:intent, fn %{session: %{id: session_id, payment_intent: intent}} ->
      Intents.changeset(intent, order_id: order.id, session_id: session_id)
    end)
  end

  defp build_stripe_customer_params(%{delivery_info: delivery_info}) do
    address = delivery_info.address || %{}

    %{
      email: delivery_info.email,
      name: delivery_info.name,
      shipping: %{
        name: delivery_info.name,
        address: %{
          country: Map.get(address, :country),
          line1: Map.get(address, :addr1),
          line2: Map.get(address, :addr2),
          postal_code: Map.get(address, :zip),
          state: Map.get(address, :state),
          city: Map.get(address, :city)
        }
      }
    }
  end

  defp shipping_options(%{products: [_ | _] = products} = order) do
    products = Enum.filter(products, & &1.shipping_type)
    shipping = Cart.total_shipping(order)
    {min, max} = Cart.shipping_days(products)

    [
      %{
        shipping_rate_data: %{
          type: "fixed_amount",
          fixed_amount: %{
            amount: shipping.amount,
            currency: shipping.currency
          },
          delivery_estimate: %{
            minimum: %{unit: "day", value: min},
            maximum: %{unit: "day", value: max}
          },
          display_name: "Estimate Delivery"
        }
      }
    ]
  end

  defp shipping_options(%{products: []}), do: []

  defp place_order(cart), do: Order.placed_changeset(cart)
  defp client_total(_repo, %{cart: cart}), do: {:ok, Order.total_cost(cart)}

  defp fetch_previous_stripe_intent(
         _repo,
         %{
           previous_intent: %{
             stripe_payment_intent_id: id,
             order: %{gallery: %{organization: %{stripe_account_id: stripe_account_id}}}
           }
         }
       ),
       do: Payments.retrieve_payment_intent(id, connect_account: stripe_account_id)

  defp build_line_items(%Order{digitals: digitals, products: products} = order) do
    for item <- Enum.concat([products, digitals, [order]]), reduce: [] do
      line_items ->
        case item |> Map.put(:currency, order.currency) |> to_line_item() do
          %{
            image: image,
            name: name,
            price: price,
            tax: tax
          } ->
            [
              %{
                price_data: %{
                  currency: price.currency,
                  unit_amount: price.amount,
                  product_data: %{
                    name: name,
                    images: [item_image_url(image)],
                    tax_code: Todoplace.Payments.tax_code(tax)
                  },
                  tax_behavior: "exclusive"
                },
                quantity: 1
              }
              | line_items
            ]

          _ ->
            line_items
        end
    end
    |> Enum.reverse()
  end

  defp to_line_item(%Digital{} = digital) do
    %{
      image: digital,
      name: "Digital image",
      price: Digital.charged_price(digital),
      tax: :digital
    }
  end

  defp to_line_item(%Product{} = product) do
    %{
      image: product,
      name: "#{product_name(product)} (Qty #{product_quantity(product)})",
      price: Product.charged_price(product),
      tax: :product,
      total_markuped_price: product.total_markuped_price
    }
  end

  defp to_line_item(%Order{bundle_price: %Money{}} = order) do
    %{
      price: order.bundle_price,
      tax: :digital,
      name: "Bundle - all digital downloads",
      image: {:bundle, order.gallery}
    }
  end

  defp to_line_item(%Order{}), do: nil

  defp run(multi, name, fun, args), do: Ecto.Multi.run(multi, name, __MODULE__, fun, args)
end
