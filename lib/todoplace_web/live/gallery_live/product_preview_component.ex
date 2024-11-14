defmodule TodoplaceWeb.GalleryLive.ProductPreviewComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  @default_assigns %{
    click_params: nil
  }

  def update(assigns, socket) do
    socket |> assign(@default_assigns) |> assign(assigns) |> ok()
  end

  defdelegate framed_preview(assigns), to: TodoplaceWeb.GalleryLive.FramedPreviewComponent
  defdelegate min_price(category, org_id, opts), to: Todoplace.Galleries
end
