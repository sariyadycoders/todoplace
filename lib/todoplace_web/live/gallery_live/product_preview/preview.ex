defmodule TodoplaceWeb.GalleryLive.ProductPreview.Preview do
  @moduledoc "no doc"

  use TodoplaceWeb, :live_component
  alias Todoplace.{GalleryProducts, Utils}
  import TodoplaceWeb.GalleryLive.Shared, only: [toggle_preview: 1]

  def update(%{product: product, gallery: gallery} = assigns, socket) do
    currency = Todoplace.Currency.for_gallery(gallery)

    socket
    |> assign(assigns)
    |> assign(currency: currency)
    |> assign(products_currency: Utils.products_currency())
    |> assign(category: product.category, photo: product.preview_photo, product_id: product.id)
    |> ok()
  end

  def handle_event("sell_product_enabled", _, %{assigns: %{product: product}} = socket) do
    socket
    |> assign(product: GalleryProducts.toggle_sell_product_enabled(product))
    |> noreply()
  end

  def handle_event("product_preview_enabled", _, %{assigns: %{product: product}} = socket) do
    socket
    |> assign(product: GalleryProducts.toggle_product_preview_enabled(product))
    |> noreply()
  end

  @spec render(any) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
      <div class="flex flex-col justify-between">
        <div class="items-center mt-8">
          <div class={classes("flex items-center pt-4 font-sans lg:text-lg text-2xl font-bold", %{"text-gray-400" => @category.coming_soon})}>
            <%= @category.name %>
          </div>
          <div class=" mx-4 pt-4 flex flex-col justify-between" >
            <.toggle_preview
            disabled={@disabled || @currency not in Utils.products_currency()}
            click="sell_product_enabled"
            checked={@product.sell_product_enabled}
            text="Product enabled to sell"
            myself={@myself} />
          </div>

          <div class={classes("mt-4 pb-4 bg-gray-200", %{"bg-gray-200/20" => @category.coming_soon})}>
            <div class=" mx-4 pt-4 flex flex-col justify-between" >
              <%= if @product.sell_product_enabled do %>
                <.toggle_preview
                disabled={@disabled}
                click="product_preview_enabled"
                checked={@product.product_preview_enabled}
                text="Show product preview in gallery"
                myself={@myself} />
              <% end %>
            </div>

            <div class={classes("mt-4 pb-4 bg-gray-200", %{"bg-gray-200/20" => @category.coming_soon})}>
              <div class="flex justify-start pt-4 pl-4">
                <%= if @category.coming_soon do %>
                  <button class="p-2 font-bold rounded-lg text-blue-planning-300 bg-blue-planning-100" disabled>
                    Coming soon!
                  </button>
                <% else %>
                  <%= if @product.product_preview_enabled and @product.sell_product_enabled do %>
                    <button
                    class={classes("flex items-center font-sans text-sm py-2 pr-3.5 pl-3 bg-white border border-blue-planning-300 rounded-lg cursor-pointer", %{"pointer-events-none opacity-30 hover:opacity-30 hover:cursor-not-allowed" => @disabled})}
                    phx-click="edit"
                    id={"product-id-#{@product_id}"}
                    phx-value-product_id={@product_id}>
                      <.icon name="pencil" class="mr-2.5 w-3 h-3 fill-current text-blue-planning-300" />
                      <span>Edit product preview</span>
                    </button>
                  <% end %>
                <% end %>
              </div>

              <div class="flex items-center justify-center mt-4">
                <.framed_preview category={@category} photo={@photo} />
              </div>
            </div>
          </div>
        </div>
      </div>
    """
  end

  defdelegate framed_preview(assigns), to: TodoplaceWeb.GalleryLive.FramedPreviewComponent
end
