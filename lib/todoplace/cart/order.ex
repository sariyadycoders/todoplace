defmodule Todoplace.Cart.Order do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Todoplace.{
    Cart,
    Cart.DeliveryInfo,
    Cart.Digital,
    Cart.OrderNumber,
    Cart.Product,
    Galleries.Gallery,
    Galleries.GalleryClient,
    Galleries.Album,
    Intents.Intent
  }

  schema "gallery_orders" do
    field :bundle_price, Money.Ecto.Map.Type
    field :number, :integer, default: Enum.random(100_000..999_999)
    field :placed_at, :utc_datetime
    field :total_credits_amount, :integer, default: 0

    belongs_to(:gallery_client, GalleryClient)
    belongs_to(:gallery, Gallery)
    belongs_to(:album, Album)

    belongs_to(:order_currency, Todoplace.Currency,
      references: :code,
      type: :string,
      foreign_key: :currency
    )

    has_one :package, through: [:gallery, :package]
    has_one :invoice, Todoplace.Invoices.Invoice

    has_one :intent, Intent,
      where: [status: {:fragment, "? != 'canceled'"}],
      on_delete: :delete_all

    has_many :canceled_intents, Intent, where: [status: :canceled], on_delete: :delete_all

    has_many :digitals, Digital,
      on_replace: :delete,
      on_delete: :delete_all,
      preload_order: [desc: :id]

    has_many :products, Product,
      on_replace: :delete,
      on_delete: :delete_all,
      preload_order: [desc: :id]

    embeds_one :delivery_info, DeliveryInfo, on_replace: :delete
    embeds_one :whcc_order, Todoplace.WHCC.Order.Created, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def changeset(product, attrs \\ %{}, opts \\ [])

  def changeset(%Product{} = product, attrs, opts) do
    attrs
    |> do_changeset()
    |> put_assoc(:products, [
      Product.update_price(product,
        credits: get_in(opts, [:credits, :print]) || Money.new(0)
      )
    ])
  end

  def changeset(%Digital{} = digital, attrs, opts) do
    attrs
    |> do_changeset()
    |> put_assoc(:digitals, [%{digital | is_credit: is_credit(opts)}])
  end

  def changeset({:bundle, price}, attrs, _opts) do
    attrs
    |> do_changeset()
    |> put_change(:bundle_price, price)
  end

  defp do_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:gallery_id, :gallery_client_id, :album_id, :currency])
    |> validate_required([:gallery_id, :gallery_client_id])
    |> foreign_key_constraint(:gallery_id)
    |> foreign_key_constraint(:gallery_client_id)
  end

  def update_changeset(order, product, attrs \\ %{}, opts \\ [])

  def update_changeset(order, {:bundle, price}, attrs, _opts) do
    order
    |> cast(attrs, [])
    |> put_change(:bundle_price, price)
    |> put_assoc(:digitals, [])
  end

  def update_changeset(%{products: products} = cart, %Product{} = product, attrs, opts)
      when is_list(products) do
    {products, opts} = remaining_products(products, product.editor_id, opts)

    cart
    |> cast(Map.put(attrs, :products, update_prices([product | products], opts)), [])
    |> cast_assoc(:products)
  end

  def update_changeset(%__MODULE__{digitals: digitals} = order, %Digital{} = digital, attrs, opts)
      when is_list(digitals) do
    order
    |> cast(attrs, [])
    |> put_assoc(:digitals, [%{digital | is_credit: is_credit(opts)} | digitals])
  end

  def whcc_order_changeset(%{products: products} = order, params) when is_list(products) do
    order
    |> cast(%{whcc_order: params}, [])
    |> cast_embed(:whcc_order)
  end

  def placed_changeset(order),
    do: change(order, %{placed_at: DateTime.utc_now() |> DateTime.truncate(:second)})

  def whcc_confirmation_changeset(%__MODULE__{whcc_order: %{entry_id: entry_id}} = order) do
    order
    |> cast(%{whcc_order: %{entry_id: entry_id, confirmed_at: DateTime.utc_now()}}, [])
    |> cast_embed(:whcc_order)
  end

  def store_delivery_info(order, delivery_info_changeset) do
    order
    |> change
    |> put_embed(:delivery_info, delivery_info_changeset)
  end

  def number(%__MODULE__{id: id}), do: OrderNumber.to_number(id)
  def number(id), do: OrderNumber.to_number(id)

  @spec delete_product_changeset(t(),
          bundle: true,
          editor_id: String.t(),
          digital_id: integer(),
          credits: %{digital: integer(), print: Money.t()}
        ) :: Ecto.Changeset.t()
  def delete_product_changeset(%__MODULE__{} = order, opts) do
    case {Keyword.take(opts, [:bundle, :editor_id, :digital_id]), order} do
      {[bundle: true], _} ->
        order
        |> change()
        |> put_change(:bundle_price, nil)

      {[editor_id: editor_id], %{products: products}} when is_list(products) ->
        {products, opts} = remaining_products(products, editor_id, opts)

        order
        |> cast(
          %{
            products: update_prices(products, opts),
            whcc_order: nil
          },
          []
        )
        |> cast_assoc(:products)
        |> cast_embed(:whcc_order)

      {[digital_id: digital_id], %{digitals: digitals}} when is_list(digitals) ->
        order_credit_count = Enum.count(digitals, & &1.is_credit)

        {_, digitals} =
          digitals
          |> Enum.reduce({0, []}, fn
            %{id: ^digital_id}, acc ->
              acc

            digital, {index, acc} ->
              {index + 1, [%{digital | is_credit: index < order_credit_count} | acc]}
          end)

        order |> change() |> put_assoc(:digitals, digitals)
    end
  end

  def placed?(%__MODULE__{placed_at: nil}), do: false
  def placed?(%__MODULE__{}), do: true

  @doc "calculate products cost, includes shipping price"
  def product_total(%__MODULE__{products: products, currency: currency} = order)
      when is_list(products) do
    for product <- products, reduce: Money.new(0, currency) do
      sum ->
        product
        |> Product.charged_price()
        |> Money.add(sum)
    end
    |> Money.add(Cart.total_shipping(order))
  end

  def digital_total(%__MODULE__{
        digitals: digitals,
        bundle_price: bundle_price,
        currency: currency
      })
      when is_list(digitals) do
    for digital <- digitals,
        digital = Map.put(digital, :currency, currency),
        reduce: bundle_price || Money.new(0, currency) do
      sum -> digital |> Digital.charged_price() |> Money.add(sum)
    end
  end

  @doc "calculate total cost, includes shipping price"
  def total_cost(%__MODULE__{} = order) do
    Money.add(digital_total(order), product_total(order))
  end

  def lines_by_product(%__MODULE__{products: products}), do: products |> sort_products()

  def canceled?(%__MODULE__{canceled_intents: [_ | _], intent: nil}), do: true
  def canceled?(_), do: false

  defp remaining_products(products, editor_id, opts) do
    case Enum.split_with(products, &(&1.editor_id == editor_id)) do
      {[], products} ->
        {products, opts}

      {[%{print_credit_discount: unused_discount}], products} ->
        {products, update_in(opts, [:credits, :print], &Money.add(&1, unused_discount))}
    end
  end

  defp update_prices(products, opts) do
    available_credit =
      Enum.reduce(
        products,
        get_in(opts, [:credits, :print]) || Money.new(0),
        &Money.add(&1.print_credit_discount, &2)
      )

    {_credits, products} =
      for {_, line_items} <- sort_products(products),
          reduce: {available_credit, []} do
        acc ->
          for product <- line_items,
              reduce: acc do
            {credit_remaining, products} ->
              %{print_credit_discount: credit_used} =
                product =
                Product.update_price(product,
                  credits: credit_remaining
                )

              {Money.subtract(credit_remaining, credit_used), [product | products]}
          end
      end

    Enum.reverse(products)
  end

  defp sort_products(products) do
    products
    |> Todoplace.Repo.preload(whcc_product: :category)
    |> Enum.sort_by(& &1.id)
    |> Enum.reverse()
    |> Enum.group_by(fn %{whcc_product: %Todoplace.Product{category: category} = whcc_product} ->
      whcc_product
      |> Map.take([:id, :whcc_name])
      |> Map.put(:category, %{whcc_id: category.whcc_id})
    end)
    |> Enum.sort_by(fn {_whcc_product, cart_products} ->
      cart_products |> Enum.map(& &1.id) |> Enum.max()
    end)
    |> Enum.reverse()
  end

  defp is_credit(opts) do
    (get_in(opts, [:credits, :digital]) || 0) > 0
  end
end
