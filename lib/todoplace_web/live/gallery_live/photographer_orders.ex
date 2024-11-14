defmodule TodoplaceWeb.GalleryLive.PhotographerOrders do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "live"]
  alias Todoplace.{Orders, Cart, Galleries}

  def mount(%{"id" => id}, _, socket) do
    socket |> assign(gallery: Galleries.get_gallery!(id), orders: Orders.all(id)) |> ok
  end

  defdelegate total_cost(order), to: Cart
end
