defmodule TodoplaceWeb.GalleryLive.ClientShow.Cart.Summary do
  @moduledoc """
    breaks down order price in a table
  """
  use TodoplaceWeb, :live_component
  alias Phoenix.LiveView.JS
  alias Todoplace.Galleries.Gallery
  alias Todoplace.Cart
  import Money.Sigils
  import TodoplaceWeb.GalleryLive.Shared, only: [credits: 1]

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:caller, fn -> false end)
    |> then(fn %{assigns: %{id: id, order: order, caller: caller}} = socket ->
      socket
      |> assign_new(:class, fn -> id end)
      |> assign_new(:inner_block, fn -> [] end)
      |> assign(details(order, caller))
    end)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={"client-transactions-summary flex flex-col font-sans rounded-lg md:border-0 border border-base-225 #{@class}"}>
      <button type="button" phx-click={toggle(@class)} class="block px-5 pt-4 text-base-250 lg:hidden">
        <div class="flex items-center pb-2">
          <.icon name="up" class="toggle w-5 h-2.5 stroke-2 stroke-current mr-2.5" />
          <.icon name="down" class="hidden toggle w-5 h-2.5 stroke-2 stroke-current mr-2.5" />
          See&nbsp;
          <span class="toggle">more</span>
          <span class="hidden toggle">less</span>
        </div>
        <hr class="mb-1 border-base-200">
      </button>
      <.inner_content {assigns} />

      <%= render_slot(@inner_block) %>

      <.payment_options {assigns} />
    </div>
    """
  end

  defp payment_options(
         %{caller: caller, gallery: %{organization: %{payment_options: payment_options}}} =
           assigns
       )
       when caller in ~w(cart proofing_album_cart)a do
    assigns =
      Enum.into(assigns, %{
        payment_options: payment_options
      })

    ~H"""
    <div class="px-5 mb-5">
        <h3 class="uppercase text-base-250">Online payment options</h3>
        <div class="mr-auto flex flex-wrap items-center gap-4 mt-2">
          <.payment_icon icon="payment-card" option="Cards" />
          <%= if(@payment_options.allow_cash) do %>
            <.payment_icon icon="payment-offline" option="Manual payments (check/cash/Venmo/Etc)" />
          <% end %>
          <%= if(@payment_options.allow_afterpay_clearpay) do %>
            <.payment_icon icon="payment-afterpay" option="Afterpay" />
          <% end %>
          <%= if(@payment_options.allow_affirm) do %>
            <.payment_icon icon="payment-affirm" option="Affirm ($50.00 min.)" />
          <% end %>
          <%= if(@payment_options.allow_klarna) do %>
            <.payment_icon icon="payment-klarna" option="Klarna" />
          <% end %>
          <%= if(@payment_options.allow_cashapp) do %>
            <.payment_icon icon="payment-cashapp" option="Cashapp Pay" />
          <% end %>
        </div>
    </div>
    """
  end

  defp payment_options(assigns) do
    ~H"""
    """
  end

  defp inner_content(%{caller: caller} = assigns)
       when caller in ~w(order cart proofing_album_order proofing_album_cart)a do
    assigns = Map.put(assigns, :is_proofing, caller == :proofing_album_order)

    ~H"""
    <div class="px-5 grid grid-cols-[1fr,max-content] gap-3 mt-6 mb-5">
    <dl class="text-lg contents">
      <%= with [{label, value} | _] <- @product_charge_lines do %>
        <.summary_block label={label} value={value} />
      <% end %>

      <%= if Enum.any?(@order.products, & &1.total_markuped_price) do %>
        <.shipping_block {assigns} />
      <% else %>
        <.summary_block label="Shipping & handling" value="Included" />
      <% end %>

      <%= for {label, value} <- @charges do %>
        <dt class="hidden toggle lg:block"><%= label %></dt>

        <dd class="self-center hidden toggle lg:block justify-self-end"><%= value %></dd>
      <% end %>

      <dt class={"hidden #{!@is_proofing && 'text-2xl'} toggle md:block"}>
        <%= if @is_proofing, do: "Purchased", else: "Subtotal" %>
      </dt>
      <dd class={"self-center hidden #{!@is_proofing && 'text-2xl'} toggle lg:block justify-self-end"}>
        <%= @subtotal %>
      </dd>
    </dl>

    <%= unless @discounts == [] or @is_proofing do %>
      <hr class="hidden mt-2 mb-3 toggle lg:block col-span-2 border-base-200">
      <.discounts_content discounts={@discounts} class="text-lg text-green-finances-300" />
    <% end %>

    <hr class="hidden mt-2 mb-3 col-span-2 border-base-200 toggle lg:block">

    <dl class="contents">
      <dt class="text-2xl">Total</dt>

      <dd class="self-center text-2xl justify-self-end"><%= @total %></dd>
    </dl>
    </div>
    """
  end

  defp summary_block(assigns) do
    assigns = Enum.into(assigns, %{value: nil, icon: nil, class: nil, event: nil})

    ~H"""
    <dt class={"hidden toggle lg:block #{@class}"} phx-click={@event}><%= @label %></dt>
    <dd class="self-center hidden toggle lg:block justify-self-end"><%= @value %></dd>
    """
  end

  defp discounts_content(assigns) do
    ~H"""
    <dl class={"#{@class} contents"}>
      <%= for {label, value} <- @discounts do %>
        <dt class="hidden toggle lg:block"><%= label %></dt>
        <dd class="self-center hidden toggle lg:block justify-self-end">-<%= Money.neg(value) %></dd>
      <% end %>
    </dl>
    """
  end

  defp payment_icon(assigns) do
    ~H"""
    <div class="flex gap-1 items-center text-sm">
      <.icon name={@icon} class="w-4 h-4" />
      <%= @option %>
    </div>
    """
  end

  defp shipping_block(
         %{order: %{products: [_ | _] = products, delivery_info: delivery_info}} = assigns
       ) do
    {added?, description} = shipping_description(delivery_info, products)
    assigns = assign(assigns, %{description: description, added?: added?})

    ~H"""
    <.summary_block label={"Shipping #{@description}"} value={Cart.total_shipping(@order)} />

    <%= unless @order.placed_at do %>
      <.summary_block
        label={@added? && "#{zip(@order)} Edit" || "Add zipcode for actual"}
        class="mt-[-4px] text-sm underline cursor-pointer text-blue-planning-300",
        event="zipcode"
      />
    <% end %>
    """
  end

  defp zip(%{delivery_info: delivery_info}) do
    delivery_info && delivery_info |> Map.get(:address, %{}) |> Map.get(:zip)
  end

  defp shipping_description(%{address: %{zip: zip}}, products) when not is_nil(zip) do
    {true, "(#{Enum.count(products, &Cart.has_shipping?/1)})"}
  end

  defp shipping_description(_, _), do: {false, "estimated"}

  def details(%{products: products, digitals: digitals, currency: currency} = order, caller)
      when is_list(products) and is_list(digitals) do
    charges = charges(order, caller)
    product_charge = product_charge_lines(order)
    discounts = discounts(order, caller)

    %{
      charges: charges,
      product_charge_lines: product_charge,
      subtotal: sum_lines(charges ++ product_charge, currency),
      discounts: discounts,
      total: sum_lines(charges ++ product_charge ++ discounts, currency)
    }
  end

  def summary(assigns) do
    assigns =
      assign_new(assigns, :id, fn -> "summary-for-order-#{Map.get(assigns, :order).id}" end)

    ~H"""
    <.live_component module={__MODULE__} {assigns} />
    """
  end

  defp toggle(class),
    do: JS.toggle(to: ".#{class} > button .toggle") |> JS.toggle(to: ".#{class} .grid .toggle")

  defp sum_lines(charges, currency) do
    for {_label, %Money{} = price} <- charges, reduce: Money.new(0, currency) do
      acc -> Money.add(acc, price)
    end
  end

  defp sum_prices(items, currency) do
    for %{price: price} <- items, reduce: Money.new(0, currency) do
      acc -> Money.add(acc, price)
    end
  end

  defp discounts(order, caller) do
    product_discount_lines(order) ++
      print_credit_lines(order) ++ digital_discount_lines(order, caller)
  end

  defp charges(order, caller) do
    digital_charge_lines(order, caller) ++ bundle_charge_lines(order)
  end

  defp product_charge_lines(%{products: []}), do: []

  defp product_charge_lines(%{products: products, currency: currency} = order) do
    [
      {"Products (#{length(products)})", sum_prices(products, currency)},
      Enum.any?(products, & &1.shipping_type) && {"", Cart.total_shipping(order)}
    ]
  end

  defp digital_charge_lines(%{digitals: []}, _), do: []

  @proofing_album_calls ~w(proofing_album_cart proofing_album_order)a
  defp digital_charge_lines(%{digitals: digitals, currency: currency}, caller)
       when caller in @proofing_album_calls do
    [{"Selected for retouching (#{length(digitals)})", sum_prices(digitals, currency)}]
  end

  defp digital_charge_lines(%{digitals: digitals, currency: currency}, _caller) do
    [{"Digital downloads (#{length(digitals)})", sum_prices(digitals, currency)}]
  end

  defp bundle_charge_lines(%{bundle_price: nil}), do: []

  defp bundle_charge_lines(%{bundle_price: price}),
    do: [{"Bundle - all digital downloads", price}]

  defp product_discount_lines(%{products: products}) do
    for %{volume_discount: discount} <- products, reduce: ~M[0]USD do
      acc -> Money.subtract(acc, discount)
    end
    |> case do
      ~M[0]USD -> []
      discount -> [{"Volume discount", discount}]
    end
  end

  defp digital_discount_lines(%{gallery_id: gallery_id, currency: currency} = order, caller) do
    case Enum.filter(order.digitals, & &1.is_credit) do
      [] ->
        []

      credited ->
        credit = length(credited)
        gallery = Todoplace.Repo.get(Gallery, gallery_id)

        [
          {credit(gallery, credit, caller),
           credited |> Enum.reduce(Money.new(0, currency), &Money.subtract(&2, &1.price))}
        ]
    end
  end

  defp print_credit_lines(%{products: products}) do
    products
    |> Enum.reduce(~M[0]USD, &Money.add(&2, &1.print_credit_discount))
    |> case do
      ~M[0]USD -> []
      credit -> [{"Print credits used", Money.neg(credit)}]
    end
  end

  defp credit(gallery, credit, caller) do
    if caller == :proofing_album_order do
      remainig_credit = gallery |> credits() |> find_digital() |> elem(1)

      "#{credit} credit used - #{remainig_credit} credits remainig"
    else
      "Digital download credit (#{credit})"
    end
  end

  defp find_digital([{:digital, value} | _]), do: {:digital, value}
  defp find_digital(_credits), do: {:digital, 0}
end
