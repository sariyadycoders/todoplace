defmodule TodoplaceWeb.Live.Pricing.Category do
  @moduledoc false
  use TodoplaceWeb, :live_view

  @impl true
  def mount(%{"category_id" => id}, _session, socket) do
    socket |> assign_category(id) |> assign(expanded: MapSet.new()) |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="px-6 py-8 center-container">
        <div class="flex items-center">
          <.live_link to={~p"/pricing"} class="flex items-center justify-center mr-4 rounded-full w-9 h-9 bg-blue-planning-300">
            <.icon name="back" class="w-2 h-4 stroke-current stroke-2 text-base-100" />
          </.live_link>

          <.crumbs class="text-blue-planning-200">
            <:crumb to={~p"/users/settings"}>Settings</:crumb>
            <:crumb to={~p"/pricing"}>Gallery Store Pricing</:crumb>
            <:crumb><%= @category.name %></:crumb>
          </.crumbs>
        </div>

        <div class="flex items-end justify-between mt-4">
          <h1 class="text-4xl font-bold">Adjust Pricing: <span class="font-medium"><%= @category.name %></span></h1>
          <button title="Expand All" type="button" class="items-center hidden p-3 border rounded-lg sm:flex border-base-300" phx-click="toggle-expand-all">
            <%= if all_expanded?(@category.products, @expanded) do %>
              <.icon name="up" class="w-4 h-2 mr-2 stroke-current stroke-2" /> Collapse All
            <% else %>
              <.icon name="down" class="w-4 h-2 mr-2 stroke-current stroke-2" /> Expand All
            <% end %>
          </button>
        </div>
      </div>
    </div>

    <div class="px-6 pt-8 center-container">
      <%= for product <- @category.products do %>
        <.product product={product} user={@current_user} expanded={MapSet.member?(@expanded, product.id)} />
      <% end %>
    </div>

    <button title="Expand All" type="button" class="flex items-center justify-center p-3 mx-6 mt-12 font-semibold border rounded-lg sm:hidden border-base-300" phx-click="toggle-expand-all">
      <%= if all_expanded?(@category.products, @expanded) do %>
        <.icon name="up" class="w-4 h-2 mr-2 stroke-current stroke-2" /> Collapse All
      <% else %>
        <.icon name="down" class="w-4 h-2 mr-2 stroke-current stroke-2" /> Expand All
      <% end %>
    </button>
    """
  end

  @impl true
  def handle_event(
        "toggle-expand-all",
        %{},
        %{assigns: %{expanded: expanded, category: %{products: products}}} = socket
      ) do
    if all_expanded?(products, expanded) do
      assign(socket, :expanded, MapSet.new())
    else
      assign(
        socket,
        :expanded,
        id_set(products)
      )
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "toggle-expand",
        %{"product-id" => product_id},
        %{assigns: %{expanded: expanded}} = socket
      ) do
    product_id = String.to_integer(product_id)

    expanded =
      if(MapSet.member?(expanded, product_id),
        do: MapSet.delete(expanded, product_id),
        else: MapSet.put(expanded, product_id)
      )

    socket |> assign(:expanded, expanded) |> noreply()
  end

  defp all_expanded?(products, expanded), do: products |> id_set() |> MapSet.equal?(expanded)

  defp id_set(products), do: products |> Enum.map(& &1.id) |> MapSet.new()

  defp product(assigns) do
    ~H"""
    <.live_component module={__MODULE__.Product} product={@product} id={@product.id} expanded={@expanded} user={@user} />
    """
  end

  defp assign_category(socket, id) do
    assign(socket, category: Todoplace.WHCC.category(id))
  end
end
