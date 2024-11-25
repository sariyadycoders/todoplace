defmodule TodoplaceWeb.GalleryLive.GlobalSettings.ProductComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  alias Todoplace.{GlobalSettings, Category, Galleries, UserCurrencies}
  import TodoplaceWeb.GalleryLive.Shared, only: [toggle_preview: 1]
  import Todoplace.Utils, only: [products_currency: 0]

  @impl true
  def update(%{organization_id: organization_id} = assigns, socket) do
    user_currency = UserCurrencies.get_user_currency(organization_id)

    socket
    |> assign(assigns)
    |> assign(currency: user_currency.currency)
    |> assign(products_currency: products_currency())
    |> assign_products()
    |> ok()
  end

  defp assign_products(%{assigns: %{organization_id: organization_id}} = socket) do
    assign(
      socket,
      :products,
      GlobalSettings.list_gallery_products(organization_id)
    )
  end

  defp product_preview(assigns) do
    ~H"""
    <div class="flex flex-col justify-between">
      <div class="items-center mt-8">
        <div class="flex items-center pt-4 font-sans lg:text-xl text-2xl font-bold">
          <%= @product.category.name %>
        </div>
        <div class="pt-4 flex flex-col justify-between">
          <.toggle_preview
            click="product_enabled"
            checked={@product.sell_product_enabled}
            text="Product enabled to sell"
            product_id={@product.id}
            myself={@myself}
            disabled={@currency not in products_currency()}
          />
        </div>

        <div class={"mt-4 border border-base-250 rounded-md #{!@product.sell_product_enabled && 'pointer-events-none bg bg-gray-100'}"}>
          <div class="py-2 px-4 flex justify-between">
            <div>
              <h4 class="font-bold text-xl">Pricing:</h4>
              <i class="font-normal text-sm text-base-250">
                From <%= min_price(@product.category, @organization_id, %{
                  use_global: %{products: true}
                }) %> - <%= max_price(@product.category, @organization_id, %{
                  use_global: %{products: true}
                }) %>
              </i>
            </div>
            <%= if @product.category.whcc_id == Category.print_category() do %>
              <div
                phx-target={@myself}
                phx-click="edit_pricing"
                phx-value-product_id={@product.id}
                class="mt-2 h-12 text-base font-normal border rounded-md border-blue-planning-300 p-3 text-center flex justify-between cursor-pointer"
              >
                Edit Pricing
                <.icon
                  name="forth"
                  class="w-3 h-3 mt-2 ml-1 stroke-current text-blue-planning-300 stroke-2"
                />
              </div>
            <% else %>
              <div>
                <.form :let={f} for={%{}} as={:product} phx-change="markup" phx-target={@myself}>
                  <span class="font-bold text-sm mr-2">Markup by</span>
                  <%= text_input(f, :markup,
                    onkeydown: "return event.key != 'Enter';",
                    class:
                      "text-input w-24 mt-2 h-12 border rounded-md border-blue-planning-300 p-4 text-center",
                    phx_hook: "PercentMask",
                    value: "#{Decimal.mult(@product.markup, 100)}%"
                  ) %>
                  <%= hidden_input(f, :product_id, value: @product.id) %>
                </.form>
              </div>
            <% end %>
          </div>
          <div class="bg-gray-200 pb-4">
            <div class="mt-2 py-4 bg-gray-200">
              <div class="flex items-center justify-center mt-4">
                <.framed_preview category={@product.category} />
              </div>
            </div>
            <div class="mx-4 pt-4 flex flex-col justify-between">
              <.toggle_preview
                click="show_product_preview"
                checked={@product.product_preview_enabled}
                product_id={@product.id}
                text="Show product preview in gallery"
                myself={@myself}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defdelegate framed_preview(assigns), to: TodoplaceWeb.GalleryLive.FramedPreviewComponent

  @impl true
  def handle_event("product_enabled", %{"product_id" => product_id, "value" => "on"}, socket) do
    update_settings(socket, product_id, sell_product_enabled: true)
  end

  def handle_event("product_enabled", %{"product_id" => product_id}, socket) do
    update_settings(socket, product_id, sell_product_enabled: false)
  end

  def handle_event("show_product_preview", %{"product_id" => product_id, "value" => "on"}, socket) do
    update_settings(socket, product_id, product_preview_enabled: true)
  end

  def handle_event("show_product_preview", %{"product_id" => product_id}, socket) do
    update_settings(socket, product_id, product_preview_enabled: false)
  end

  def handle_event("markup", %{"product" => params}, socket) do
    %{"markup" => markup, "product_id" => product_id} = params
    update_settings(socket, product_id, %{markup: markup(markup)})
  end

  def handle_event(
        "edit_pricing",
        %{"product_id" => product_id},
        socket
      ) do
    socket
    |> push_patch(
      to: ~p"/galleries/settings?#{%{section: "print_product", product_id: product_id}}"
    )
    |> noreply()
  end

  defp update_settings(%{assigns: %{products: products}} = socket, product_id, opts) do
    products
    |> Enum.find(&(to_string(&1.id) == product_id))
    |> GlobalSettings.update_gallery_product(opts)
    |> then(fn {:ok, _} -> socket |> assign_products |> noreply() end)
  end

  defp markup("%"), do: markup("0%")
  defp markup(markup), do: String.trim(markup, "%") |> Decimal.new() |> Decimal.div(100)

  defdelegate min_price(category, org_id, opts), to: Galleries
  defdelegate max_price(category, org_id, opts), to: Galleries
end
