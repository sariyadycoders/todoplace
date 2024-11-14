defmodule TodoplaceWeb.GalleryLive.ClientShow.Cart do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "live_gallery_client"]

  alias Todoplace.{Cart, Cart.Order, WHCC, Galleries}
  alias Todoplace.Shipment.{Detail, DasType}
  alias TodoplaceWeb.GalleryLive.ClientMenuComponent
  alias TodoplaceWeb.Endpoint
  alias Todoplace.Cart.DeliveryInfo
  alias Todoplace.Repo
  alias Ecto.Multi
  import TodoplaceWeb.GalleryLive.Shared
  import Money.Sigils

  require Logger
  import TodoplaceWeb.Live.Profile.Shared, only: [photographer_logo: 1]

  @default_shipping "economy"
  @products_config Application.compile_env!(:todoplace, :products)
  @shipping_to_all [@products_config[:whcc_album_id], @products_config[:whcc_books_id]]

  @impl true
  def mount(
        _params,
        _session,
        %{assigns: %{gallery: gallery, client_email: client_email} = assigns} = socket
      ) do
    gallery = Todoplace.Repo.preload(gallery, [:gallery_digital_pricing, :organization])

    gallery =
      Map.put(
        gallery,
        :credits_available,
        (client_email && client_email in gallery.gallery_digital_pricing.email_list) ||
          is_photographer_view(assigns)
      )

    organization =
      gallery
      |> Map.get(:organization)

    socket
    |> assign(
      gallery: gallery,
      organization: organization,
      credits_available: gallery.credits_available,
      open_profile_logout?: false,
      client_menu_id: "clientMenu",
      gallery_client: get_client_by_email(assigns)
    )
    |> assign_is_proofing()
    |> then(
      &(&1
        |> get_unconfirmed_order(preload: [:products, :digitals, :package])
        |> case do
          {:ok, order} ->
            &1
            |> assign(:order, order)
            |> assign_das_type()
            |> assign_products_shipping()

          {:error, _} ->
            &1
            |> assign_checkout_routes()
            |> maybe_redirect()
        end)
    )
    |> assign_cart_count(gallery)
    |> assign_credits(gallery)
    |> assign_checkout_routes()
    |> assign(:shipping_to_all, @shipping_to_all)
    |> assign(:default_shipping, @default_shipping)
    |> assign(:shipment_details, Detail.all())
    |> ok()
  end

  defp assign_das_type(%{assigns: %{order: order}} = socket) do
    case order do
      %{delivery_info: %{address: %{zip: zipcode}}} when not is_nil(zipcode) ->
        assign(socket, :das_type, DasType.get_by_zipcode(zipcode))

      _ ->
        socket |> assign(:das_type, nil)
    end
  end

  @impl true
  def handle_params(
        _params,
        _uri,
        %{
          assigns: %{
            order: order,
            gallery: %{job: %{client: %{organization: organization}}},
            live_action: live_action
          }
        } = socket
      )
      when live_action in ~w(address proofing_album_address)a do
    socket
    |> assign(
      delivery_info_changeset: Cart.delivery_info_change(order),
      organization: organization,
      checking_out: false
    )
    |> noreply()
  end

  def handle_params(_params, _uri, socket), do: noreply(socket)

  @impl true
  def handle_event(
        "checkout",
        _,
        %{
          assigns: %{
            delivery_info_changeset: delivery_info_changeset,
            order: order
          }
        } = socket
      ) do
    Multi.new()
    |> Multi.run(:order, fn _, _ ->
      delivery_info_changeset = Map.put(delivery_info_changeset, :action, nil)
      Cart.store_order_delivery_info(order, delivery_info_changeset)
    end)
    |> Multi.run(:update_shipping, fn _, _ ->
      {:ok, order} =
        get_unconfirmed_order(socket,
          preload: [:products, :digitals, :package]
        )

      unless Enum.empty?(order.products) do
        %{delivery_info: %{address: %{zip: zipcode}}} = order
        das_type = DasType.get_by_zipcode(zipcode)
        Cart.add_default_shipping_to_products(order, %{das_type: das_type, force_update: true})
      end
      Logger.info("shipping updated")
      {:ok, :updated}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} ->
        socket
        |> cart_checkout(order)
        |> noreply()

      {:error, :order, changeset, _} ->
        Logger.info("error in chageset: #inspect({changeset})")
        socket
        |> assign(:delivery_info_changeset, changeset)
        |> noreply()
      error ->
        Logger.info("some other error in chageset: #inspect({error})")

        socket
        |> noreply()
    end
  end

  def handle_event(
        "profile_logout",
        _,
        %{assigns: %{open_profile_logout?: open_profile_logout?}} = socket
      ) do
    socket
    |> assign(open_profile_logout?: !open_profile_logout?)
    |> noreply()
  end

  @impl true
  def handle_event(
        "edit_product",
        %{"editor-id" => editor_id},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    %{url: url} =
      gallery
      |> Galleries.account_id()
      |> WHCC.get_existing_editor(editor_id)

    socket
    |> redirect(external: url)
    |> noreply()
  end

  def handle_event(
        "delete",
        params,
        %{
          assigns: %{
            order: order,
            client_menu_id: client_menu_id,
            cart_count: count,
            gallery: gallery
          }
        } = socket
      ) do
    item =
      case params do
        %{"editor-id" => editor_id} -> [editor_id: editor_id]
        %{"digital-id" => digital_id} -> [digital_id: String.to_integer(digital_id)]
        %{"bundle" => _} -> [bundle: true]
      end

    case Cart.delete_product(order, gallery, item) do
      {:deleted, _} ->
        socket
        |> assign(order: nil)
        |> maybe_redirect()

      {:loaded, order} ->
        digital_items = Enum.map(order.digitals, fn digital -> Map.drop(digital, [:photo]) end)

        digital_items
        |> Enum.reduce(Ecto.Multi.new(), fn %{id: id} = digital, multi ->
          Cart.Digital
          |> Repo.get(id)
          |> Ecto.Changeset.change(is_credit: digital.is_credit)
          |> then(&Ecto.Multi.update(multi, id, &1))
        end)
        |> Repo.transaction()

        send_update(ClientMenuComponent, id: client_menu_id, cart_count: count - 1)

        assign(socket, :order, order)
    end
    |> assign_cart_count(gallery)
    |> assign_credits(gallery)
    |> assign_products_shipping()
    |> noreply()
  end

  def handle_event(
        "validate_delivery_info",
        %{"delivery_info" => params},
        %{assigns: %{order: order}} = socket
      ) do
    socket
    |> assign(
      :delivery_info_changeset,
      order |> Cart.delivery_info_change(params) |> Map.put(:action, :validate)
    )
    |> noreply()
  end

  def handle_event(
        "place_changed",
        params,
        %{assigns: %{order: order, delivery_info_changeset: changeset}} = socket
      ) do
    socket
    |> assign(delivery_info_changeset: Cart.delivery_info_change(order, changeset, params))
    |> noreply()
  end

  def handle_event(
        "shiping_type",
        %{"shipping" => %{"product_id" => product_id, "type" => type}},
        %{assigns: %{das_type: das_type, order: %{products: products}}} = socket
      ) do
    products
    |> Enum.map(&update_product(&1, product_id, %{shipping_type: type, das_type: das_type}))
    |> assign_products(socket)
    |> noreply()
  end

  def handle_event("zipcode", %{}, %{assigns: %{order: %{delivery_info: delivery_info}}} = socket) do
    TodoplaceWeb.Shared.InputComponent.open(
      socket,
      %{
        title: "Add your zip code",
        subtitle: "Zip code",
        placeholder: "enter zipcode..",
        save_event: "zipcode",
        change_event: "zipcode_change",
        input_value: delivery_info && Map.get(delivery_info.address, :zip)
      }
    )
    |> noreply()
  end

  @impl true
  defdelegate handle_event(name, params, socket), to: TodoplaceWeb.GalleryLive.Shared

  defp cart_checkout(%{assigns: %{checkout_routes: checkout_routes}} = socket, order) do
    Logger.info("cart_checkout method reached for #{inspect(order.id)} -----------------")
    order
    |> Cart.checkout(
      success_url:
        Enum.join(
          [
            Endpoint.url() <> checkout_routes.order_paid,
            "session_id={CHECKOUT_SESSION_ID}"
          ],
          "?"
        ),
      cancel_url: Endpoint.url() <> checkout_routes.cart,
      helpers: TodoplaceWeb.Helpers
    )
    |> case do
      :ok ->
        socket |> assign(:checking_out, true) |> push_event("scroll:lock", %{})

      _error ->
        socket |> put_flash(:error, "Something went wrong")
    end
  end

  defp assign_products_shipping(%{assigns: %{order: nil}} = socket), do: socket

  defp assign_products_shipping(
         %{assigns: %{order: order, das_type: das_type}} = socket,
         force_update \\ false
       ) do
    order
    |> Cart.add_default_shipping_to_products(%{das_type: das_type, force_update: force_update})
    |> assign_products(socket)
  end

  def assign_products(products, %{assigns: %{order: order}} = socket) do
    order
    |> Map.put(:products, products)
    |> then(&assign(socket, :order, &1))
  end

  defp update_product(product, product_id, details) do
    case to_string(product.id) do
      ^product_id -> add_shipping_details!(product, details)
      _ -> product
    end
  end

  @impl true
  @doc "called when checkout completes"
  def handle_info(
        {:checkout, :complete, %Order{}},
        %{assigns: %{gallery: _gallery, checkout_routes: checkout_routes}} = socket
      ) do
    socket
    |> push_redirect(to: checkout_routes.order_paid, replace: true)
    |> push_event("scroll:unlock", %{})
    |> noreply()
  end

  @impl true
  def handle_info({:checkout, :due, stripe_url}, socket) do
    Logger.info("redirect to stripe")
    socket |> redirect(external: stripe_url) |> noreply()
  end

  def handle_info({:checkout, :error, _error}, socket) do
    socket
    |> put_flash(:error, "something went wrong")
    |> assign(:checking_out, false)
    |> push_event("scroll:unlock", %{})
    |> noreply()
  end

  def handle_info({:save_event, "zipcode", %{"input" => input}}, socket) do
    %{assigns: %{order: order}} = socket

    Repo.transaction(fn ->
      changeset = DeliveryInfo.changeset_for_zipcode(%{"address" => %{"zip" => input}})

      {:ok, _order} = Cart.store_order_delivery_info(order, changeset)

      {:ok, order} =
        get_unconfirmed_order(socket,
          preload: [:products, :digitals, :package]
        )

      socket
      |> assign(:order, order)
      |> assign_das_type()
      |> assign_products_shipping(true)
    end)
    |> then(fn {:ok, socket} -> socket end)
    |> close_modal()
    |> noreply()
  end

  @impl true
  defdelegate handle_info(message, socket), to: TodoplaceWeb.GalleryLive.Shared

  defp continue_summary(assigns) do
    ~H"""
    <.summary caller={checkout_type(@is_proofing)} order={@order} id={@id} gallery={@gallery}>
      <.link patch={@checkout_routes.cart_address} class="mx-5 text-lg mb-7 btn-primary text-center">
        Continue
      </.link>
    </.summary>
    """
  end

  defp top_section(assigns) do
    {back_route, back_btn, title} = top_section_content(assigns)
    assigns = assign(assigns, title: title, back_btn: back_btn, back_route: back_route)

    ~H"""
    <.link navigate={@back_route} class="flex w-32 font-extrabold text-base-250 items-center mt-6 lg:mt-8 px-4 md:px-0">
      <.icon name="back" class="h-3.5 w-1.5 stroke-2 mr-2" />
      <p class="mt-1"><%= @back_btn %></p>
    </.link>

    <div class="py-5 lg:pt-8 lg:pb-10 px-4 md:px-0">
      <div class="text-xl lg:text-3xl"><%= @title %></div>
      <%= if @title != "Review Selections" do%>
        <div class="mt-2 text-lg">
          Choose how you want your items shipped; certain types of items will ship separately.
          Shipping estimates don’t include printing/production turnaround times.
        </div>
      <% end %>
    </div>
    """
  end

  defp top_section_content(%{
         checkout_routes: checkout_routes,
         live_action: :proofing_album,
         album: album
       }) do
    {
      checkout_routes.home_page,
      "Back to album",
      (album.is_finals && "Cart & Shipping Review") || "Review Selections"
    }
  end

  defp top_section_content(%{checkout_routes: checkout_routes}) do
    {
      checkout_routes.home_page,
      "Back to gallery",
      "Cart & Shipping Review"
    }
  end

  defp empty_cart_view(assigns) do
    ~H"""
    <div class="col-span-1 lg:col-span-2 text-lg lg:pb-24">
      <div class="flex flex-col items-center justify-center border border-base-225 flex p-8 lg:mx-8 border-t">
        <span class="flex mb-8">Oops, you haven't made any selections yet.</span>
        <span class="flex text-base-225">Go back to the album to make some now.</span>
      </div>
    </div>
    <div class="col-span-1 text-lg">
      <div class="flex flex-col items-center justify-center border border-base-225 flex p-8 border-t">
        <span class="flex mb-4">
          Total: <b>0.00</b>
        </span>
        <button disabled class="flex items-center justify-center border border-base-225 text-base-225 w-full py-2">
          Send to my photographer
          <.icon name="send" class="w-4 h-4 ml-3" />
        </button>
      </div>
    </div>
    """
  end

  defp maybe_redirect(%{assigns: %{is_proofing: true}} = socket) do
    assign(socket, :order, nil)
  end

  defp maybe_redirect(%{assigns: %{checkout_routes: checkout_routes}} = socket) do
    push_redirect(socket, to: checkout_routes.home_page)
  end

  defp assign_credits(%{assigns: %{is_proofing: true}} = socket, gallery) do
    assign(socket, :credits, credits(gallery))
  end

  defp assign_credits(%{assigns: %{is_proofing: false}} = socket, _gallery), do: socket

  defp checkout_type(true), do: :proofing_album_cart
  defp checkout_type(false), do: :cart
  defp only_digitals?(%{products: []} = order), do: digitals?(order)
  defp only_digitals?(%{products: [_ | _]}), do: false
  defp digitals?(%{digitals: [_ | _]}), do: true
  defp digitals?(%{digitals: [], bundle_price: %Money{}}), do: true
  defp digitals?(_), do: false
  defp show_cart?(:cart), do: true
  defp show_cart?(_), do: false

  defp item_id(item), do: item.editor_id

  defdelegate cart_count(order), to: Cart, as: :item_count
  defdelegate lines_by_product(order), to: Cart
  defdelegate product_quantity(product), to: Cart
  defdelegate summary(assigns), to: __MODULE__.Summary
  defdelegate details(order, caller), to: __MODULE__.Summary

  defp zero_total?(order),
    do: order |> Cart.total_cost() |> Money.zero?()

  defdelegate shipping_details(product, shipping_type), to: Todoplace.Cart
  defdelegate add_shipping_details!(product, shipping_type), to: Todoplace.Cart
  defdelegate shipping_price(product), to: Todoplace.Cart
  defdelegate add_total_markuped_sum(product, products), to: Todoplace.Cart
end
