defmodule TodoplaceWeb.GalleryLive.ProductPreview.Index do
  @moduledoc false
  use TodoplaceWeb,
    live_view: [
      layout: "live_photographer"
    ]

  import TodoplaceWeb.GalleryLive.Shared
  import TodoplaceWeb.Shared.StickyUpload, only: [sticky_upload: 1]

  alias Todoplace.{Galleries, Repo}
  alias TodoplaceWeb.GalleryLive.{ProductPreview.Preview, Shared}

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(total_progress: 0)
    |> assign(:photos_error_count, 0)
    |> ok()
  end

  @impl true
  def handle_params(%{"id" => id} = params, _, socket) do
    gallery = Galleries.get_gallery!(id) |> Repo.preload([:albums, :photographer])

    prepare_gallery(gallery)

    socket
    |> assign(
      gallery: gallery,
      page_title: page_title(socket.assigns.live_action),
      products: Galleries.products(gallery)
    )
    |> is_mobile(params)
    |> noreply()
  end

  @impl true
  def handle_event("back-to-navbar", _, %{assigns: %{is_mobile: is_mobile}} = socket) do
    socket |> assign(:is_mobile, !is_mobile) |> noreply
  end

  @impl true
  def handle_event(
        "edit",
        %{"product_id" => product_id},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    socket
    |> open_modal(
      TodoplaceWeb.GalleryLive.ProductPreview.EditProduct,
      %{product_id: product_id, gallery_id: gallery.id}
    )
    |> noreply
  end

  @impl true
  def handle_event("open-billing-portal", _, %{assigns: %{gallery: gallery}} = socket) do
    {:ok, url} =
      Todoplace.Subscriptions.billing_portal_link(
        socket.assigns.current_user,
        url(~p"/galleries/#[gallery.id]/product-preview")
      )

    socket |> redirect(external: url) |> noreply()
  end

  @impl true
  defdelegate handle_event(event, params, socket), to: TodoplaceWeb.GalleryLive.Shared

  @impl true
  def handle_info({:message_composed, message_changeset, recipients}, socket) do
    add_message_and_notify(socket, message_changeset, recipients, "gallery")
  end

  @impl true
  def handle_info({:message_composed_for_album, message_changeset, recipients}, socket) do
    add_message_and_notify(socket, message_changeset, recipients, "album")
  end

  @impl true
  def handle_info(
        {:save, %{title: title}},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    socket
    |> close_modal()
    |> assign(products: Galleries.products(gallery))
    |> put_flash(:success, "#{title} successfully updated")
    |> noreply
  end

  @impl true
  def handle_info({:gallery_progress, %{total_progress: total_progress}}, socket) do
    socket
    |> assign(:total_progress, if(total_progress == 0, do: 1, else: total_progress))
    |> noreply()
  end

  @impl true
  def handle_info({:uploading, %{success_message: success_message}}, socket) do
    socket |> put_flash(:success, success_message) |> noreply()
  end

  @impl true
  def handle_info(
        {:photos_error, %{photos_error_count: photos_error_count, entries: entries}},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    if length(entries) > 0, do: inprogress_upload_broadcast(gallery.id, entries)

    socket
    |> assign(:photos_error_count, photos_error_count)
    |> noreply()
  end

  # for validating and saving gallery name
  @impl true
  defdelegate handle_info(message, socket), to: Shared

  defp page_title(:index), do: "Product Previews"
end
