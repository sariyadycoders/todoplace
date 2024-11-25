defmodule TodoplaceWeb.GalleryLive.ClientAlbum do
  @moduledoc false

  use TodoplaceWeb,
    live_view: [
      layout: "live_gallery_client"
    ]

  import TodoplaceWeb.GalleryLive.Shared

  alias Todoplace.{Repo, Galleries, GalleryProducts, Albums, Galleries.Album, Cart, Orders}
  alias TodoplaceWeb.GalleryLive.Photos.Photo.ClientPhoto
  alias Todoplace.Galleries.PhotoProcessing.ProcessingManager
  alias Todoplace.Galleries.Watermark
  alias TodoplaceWeb.GalleryLive.Shared.DownloadLinkComponent

  @per_page 500

  @impl true
  def mount(
        _params,
        _session,
        %{assigns: %{gallery: gallery, client_email: client_email} = assigns} = socket
      ) do
    gallery =
      Map.put(
        gallery,
        :credits_available,
        (client_email && client_email in gallery.gallery_digital_pricing.email_list) ||
          is_photographer_view(assigns)
      )

    organization =
      gallery
      |> Repo.preload([:organization])
      |> Map.get(:organization)

    socket
    |> assign(gallery: gallery)
    |> assign(organization: organization)
    |> assign(open_profile_logout?: false)
    |> assign(credits_available: gallery.credits_available)
    |> assign(:photo_updates, "false")
    |> assign(:gallery_client, get_client_by_email(assigns))
    |> assign(:download_all_visible, false)
    |> assign(:selected_filter, false)
    |> assign(:digitals, %{})
    |> assign(:client_proofing, "true")
    |> stream_configure(:photos_new, dom_id: &"photos_new-#{&1.uuid}")
    |> ok()
  end

  @impl true
  def handle_params(%{"album_id" => album_id}, _, socket) do
    album = Albums.get_album!(album_id)
    if connected?(socket), do: Album.subscribe(album)

    socket
    |> assign(
      :album,
      %{is_proofing: false, is_finals: false} = album
    )
    |> assign(:is_proofing, false)
    |> assigns()
  end

  def handle_params(
        %{"editorId" => whcc_editor_id},
        _,
        %{
          assigns: %{
            album: album
          }
        } = socket
      ) do
    socket
    |> place_product_in_cart(whcc_editor_id)
    |> push_redirect(to: ~p"/album/#{album.client_link_hash}/cart")
    |> noreply()
  end

  def handle_params(%{"hash" => _hash}, _, %{assigns: %{album: album}} = socket) do
    album = album |> Repo.preload(:gallery)
    if connected?(socket), do: Album.subscribe(album)

    socket
    |> assign(:album, album)
    |> assign(:is_proofing, !album.is_finals)
    |> assigns()
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
        "load-more",
        _,
        %{
          assigns: %{
            page: page
          }
        } = socket
      ) do
    socket
    |> assign(page: page + 1)
    |> assign_photos(@per_page, nil, true)
    |> noreply()
  end

  @impl true
  def handle_event("toggle_favorites", _, %{assigns: assigns} = socket) do
    %{gallery: gallery, album: album, favorites_filter: favorites_filter} = assigns

    Galleries.get_album_photo_count(gallery.id, album.id, !favorites_filter)
    |> then(&assign(socket, :photos_count, &1))
    |> toggle_favorites(@per_page)
  end

  def handle_event("toggle_selected", _, %{assigns: assigns} = socket) do
    %{gallery: gallery, album: album, selected_filter: selected_filter} = assigns

    gallery.id
    |> Galleries.get_album_photo_count(album.id, false, !selected_filter)
    |> then(&assign(socket, :photos_count, &1))
    |> assign(:page, 0)
    |> assign(:selected_filter, !selected_filter)
    |> push_event("reload_grid", %{})
    |> assign_photos(@per_page, nil, true)
    |> noreply()
  end

  @impl true
  def handle_event("product_preview_photo_popup", %{"params" => product_id}, socket) do
    socket |> product_preview_photo_popup(product_id)
  end

  @impl true
  def handle_event(
        "product_preview_photo_popup",
        %{"photo-id" => photo_id, "template-id" => template_id},
        socket
      ) do
    socket |> product_preview_photo_popup(photo_id, template_id)
  end

  @impl true
  def handle_event("click", %{"preview_photo_id" => photo_id}, socket) do
    socket |> client_photo_click(photo_id, %{close_event: :update_assigns_state})
  end

  defdelegate handle_event(name, params, socket), to: TodoplaceWeb.GalleryLive.Shared

  def handle_info(
        {:customize_and_buy_product, whcc_product, photo, size},
        %{assigns: %{album: album, favorites_filter: favorites_filter}} = socket
      ) do
    socket
    |> customize_and_buy_product(whcc_product, photo,
      size: size,
      favorites_only: favorites_filter,
      album_id: album.id
    )
  end

  def handle_info(
        {:add_bundle_to_cart, bundle_price},
        %{assigns: %{gallery: gallery, gallery_client: gallery_client, modal_pid: modal_pid}} =
          socket
      ) do
    order = Cart.place_product({:bundle, bundle_price}, gallery, gallery_client)

    send_update(modal_pid, TodoplaceWeb.GalleryLive.ChooseBundle,
      id: TodoplaceWeb.GalleryLive.ChooseBundle,
      gallery: gallery,
      gallery_client: gallery_client
    )

    socket
    |> add_to_cart_assigns(order)
    |> close_modal()
    |> put_flash(:success, "Added!")
    |> noreply()
  end

  def handle_info({:open_choose_product, photo_id}, socket) do
    socket |> client_photo_click(photo_id)
  end

  def handle_info({:update_assigns_state, _modal}, socket) do
    socket
    |> assigns()
    |> elem(1)
    |> push_event("reload_grid", %{})
    |> noreply()
  end

  def handle_info(
        :update_client_gallery_state,
        %{assigns: %{album: album, gallery: gallery, favorites_filter: favorites_filter}} = socket
      ) do
    socket
    |> assign_count(favorites_filter, gallery)
    |> assign(
      album_favorites_count: Galleries.gallery_album_favorites_count(gallery, album.id),
      favorites_count: Galleries.gallery_favorites_count(gallery)
    )
    |> update_grid_photos(favorites_filter)
    |> noreply()
  end

  def handle_info({:pack, :ok, %{packable: %{id: packable_id}, status: status}}, socket) do
    DownloadLinkComponent.update_status(packable_id, status)

    noreply(socket)
  end

  def handle_info({:pack, _, _}, socket), do: noreply(socket)

  defdelegate handle_info(message, socket), to: TodoplaceWeb.GalleryLive.Shared

  defp assigns(
         %{assigns: %{album: album, gallery: gallery, client_email: client_email} = assigns} =
           socket
       ) do
    album = album |> Repo.preload(:photos)

    %{job: %{client: %{organization: organization}}} =
      gallery =
      gallery
      |> Repo.preload([:watermark, :gallery_digital_pricing])
      |> Galleries.populate_organization_user()

    gallery =
      Map.put(
        gallery,
        :credits_available,
        (client_email && client_email in gallery.gallery_digital_pricing.email_list) ||
          is_photographer_view(assigns)
      )

    if album.is_proofing && is_nil(gallery.watermark) do
      %{job: %{client: %{organization: %{name: name}}}} = Galleries.populate_organization(gallery)

      album.photos
      |> Enum.filter(&is_nil(&1.watermarked_url))
      |> Enum.each(&ProcessingManager.start(&1, Watermark.build(name, gallery)))
    end

    socket
    |> assign(
      album_favorites_count: Galleries.gallery_album_favorites_count(gallery, album.id),
      favorites_count: Galleries.gallery_favorites_count(gallery),
      favorites_filter: false,
      gallery: gallery,
      album_order_photos: Orders.get_all_purchased_photos_in_album(gallery, album.id),
      album: album,
      photos_count: Galleries.get_album_photo_count(gallery.id, album.id),
      page: 0,
      page_title: "Show Album",
      download_all_visible: Orders.can_download_all?(gallery),
      products: GalleryProducts.get_gallery_products(gallery, :coming_soon_false),
      credits: Cart.credit_remaining(gallery) |> credits(),
      organization: organization
    )
    |> assign_gallery_preferred_filters(organization.id)
    |> assign_cart_count(gallery)
    |> assign_photos(@per_page, nil, true)
    |> push_event("reload_grid", %{})
    |> noreply()
  end

  defp top_section(%{is_proofing: false} = assigns) do
    ~H"""
    <div class="flex items-center">
      <div class="text-lg lg:text-3xl">Your Photos</div>
      <.photos_count photos_count={@photos_count} class="ml-4" />
    </div>
    <div class="flex flex-col lg:flex-row justify-between lg:items-center my-4 w-full">
      <div class="flex items-center mt-4">
        <%= if Enum.any?(@album_order_photos) || @album.is_finals do %>
          <.download_link
            packable={@album}
            class="mr-4 px-8 font-medium text-base-300 bg-base-100 border border-base-300 min-w-[12rem] hover:text-base-100 hover:bg-base-300"
          >
            Download purchased album photos
            <.icon name="download" class="w-4 h-4 ml-2 fill-current" />
          </.download_link>
        <% end %>
      </div>
      <.toggle_filter
        title="Show favorites only"
        event="toggle_favorites"
        applied?={@favorites_filter}
        album_favorites_count={@album_favorites_count}
      />
    </div>
    """
  end

  defp top_section(%{is_proofing: true} = assigns) do
    ~H"""
    <h3 {testid("album-title")} class="text-lg lg:text-3xl"><%= @album.name %></h3>
    <p class="mt-2 text-lg font-normal">Select your favorite photos below
      and then send those selections to your photographer for retouching.</p>
    <.photos_count {assigns} />
    """
  end

  defp toggle_empty_state(assigns) do
    ~H"""
    <div class="relative justify-between mb-12 text-2xl font-bold text-center text-base-250">
      <%= if !@is_proofing do %>
        Oops, you have no liked photos!
      <% else %>
        Oops, you have no selected photos!
      <% end %>
    </div>
    """
  end

  defp photos_count(%{is_proofing: true, album: album, socket: socket} = assigns) do
    cart_route =
      ~p"/album/#{album.client_link_hash}/cart"

    assigns = assign(assigns, cart_route: cart_route)

    ~H"""
    <div class="flex flex-col justify-between w-full my-4 lg:flex-row lg:items-center">
      <div class="flex items-center">
        <.link navigate={@cart_route}>
          <button class="py-8 btn-primary">Review my Selections</button>
        </.link>
        <.photos_count photos_count={@photos_count} class="ml-4" />
      </div>
      <.toggle_filter
        title="Show selected only"
        event="toggle_selected"
        applied?={@selected_filter}
        album_favorites_count={@album_favorites_count}
      />
    </div>
    """
  end

  defp photos_count(%{photos_count: count} = assigns) do
    count = (count && "#{count} #{ngettext("photo", "photos", count)}") || "photo"
    assigns = assign(assigns, count: count)

    ~H[<div class={"text-sm lg:text-xl text-base-250 #{@class}"}><%= @count %></div>]
  end

  defp photos_count(nil), do: "photo"
  defp photos_count(count), do: "#{count} #{ngettext("photo", "photos", count)}"

  defp toggle_filter(%{applied?: applied?} = assigns) do
    class_1 = if applied?, do: ~s(bg-blue-planning-100), else: ~s(bg-gray-200)
    class_2 = if applied?, do: ~s(right-1), else: ~s(left-1)
    assigns = assign(assigns, class_1: class_1, class_2: class_2)

    ~H"""
    <%= if @album_favorites_count != 0 do %>
      <div class="flex mt-4 lg:mt-0">
        <label id="toggle_favorites" class="flex items-center cursor-pointer">
          <div class="text-sm lg:text-xl text-base-250"><%= @title %></div>

          <div class="relative ml-3">
            <input type="checkbox" class="sr-only" phx-click={@event} />

            <div class={"block h-8 border rounded-full w-14 border-blue-planning-300 #{@class_1}"}>
            </div>
            <div class={"absolute w-6 h-6 rounded-full dot top-1 bg-blue-planning-300 transition #{@class_2}"}>
            </div>
          </div>
        </label>
      </div>
    <% end %>
    """
  end

  defdelegate download_link(assigns), to: DownloadLinkComponent
end
