defmodule TodoplaceWeb.GalleryLive.Photos.Index do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "live_photographer"]

  alias Todoplace.{
    Repo,
    Galleries,
    Albums,
    Orders,
    Galleries.Watermark,
    Notifiers.UserNotifier,
    Utils,
    Cart,
    Workers.PackDigitals,
    PreferredFilter
  }

  alias Phoenix.PubSub
  alias Todoplace.Galleries.{Workers.PositionNormalizer, PhotoProcessing.ProcessingManager}

  alias TodoplaceWeb.GalleryLive.Photos.{
    PhotoPreview,
    PhotoView,
    UploadError,
    FolderUpload,
    CloudError
  }

  alias TodoplaceWeb.GalleryLive.ProductPreview.EditProduct
  alias TodoplaceWeb.GalleryLive.Albums.{AlbumThumbnail, AlbumSettings}
  alias Ecto.Multi

  alias TodoplaceWeb.GalleryLive
  alias GalleryLive.Albums.{AlbumThumbnail, AlbumSettings}
  alias GalleryLive.{Photos.FolderUpload, Shared.SideNavComponent}

  alias GalleryLive.Photos.{
    PhotographerPhoto,
    PhotoPreview,
    PhotoView,
    UploadError,
    CloudError
  }

  import TodoplaceWeb.Live.Shared, only: [make_popup: 2, save_filters: 3]
  import GalleryLive.Shared
  import TodoplaceWeb.Gettext, only: [ngettext: 3]
  import TodoplaceWeb.Shared.StickyUpload, only: [sticky_upload: 1]
  import GalleryLive.Photos.Toggle, only: [toggle: 1]
  import GalleryLive.Photos.ProofingGrid, only: [proofing_grid: 1]

  @per_page 500
  @string_length 24

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(
      albums_length: 0,
      show_favorite_toggle: false,
      total_progress: 0,
      favorites_filter: false,
      photographer_favorites_filter: false,
      client_liked_album: false,
      page: 0,
      photos_error_count: 0,
      inprogress_photos: [],
      url: static_path(TodoplaceWeb.Endpoint, "/images/gallery-icon.svg"),
      invalid_photos: [],
      pending_photos: [],
      photo_updates: "false",
      select_mode: "selected_none",
      selected_photos: [],
      selections: [],
      selection_filter: false,
      orders: [],
      selected_photo_id: nil,
      first_visit?: false,
      show_upload_remover?: false
    )
    |> stream_configure(:photos_new, dom_id: &"photos_new-#{&1.uuid}")
    |> ok()
  end

  @impl true

  def handle_params(
        %{"id" => gallery_id, "album_id" => "client_liked"} = params,
        _,
        socket
      ) do
    albums_length = length(get_all_gallery_albums(gallery_id))

    socket
    |> is_mobile(params)
    |> assign(:client_liked_album, true)
    |> assign(:favorites_filter, true)
    |> assign(:albums_length, albums_length)
    |> assigns(gallery_id, client_liked_album(gallery_id))
  end

  def handle_params(
        %{"id" => gallery_id, "album_id" => album_id} = params,
        _,
        %{assigns: %{current_user: %{organization: organization}}} = socket
      ) do
    album = Albums.get_album!(album_id) |> Repo.preload(:photos)
    orders = Orders.get_proofing_order_photos(album.id, organization.id)

    socket
    |> assign(orders: orders)
    |> assign(selection_filter: orders != [])
    |> is_mobile(params)
    |> assigns(gallery_id, album)
    |> maybe_has_selected_photo(params)
  end

  def handle_params(%{"id" => gallery_id} = params, _, socket) do
    socket
    |> is_mobile(params)
    |> assigns(gallery_id)
    |> maybe_has_selected_photo(params)
  end

  @impl true
  def handle_event("back_to_navbar", _, %{assigns: %{is_mobile: is_mobile}} = socket) do
    socket |> assign(:is_mobile, !is_mobile) |> noreply
  end

  def handle_event(
        "apply_filter_sort_by",
        %{"option" => sort_by},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      ) do
    sort_direction = Enum.find(sort_options(), fn op -> op.id == sort_by end).direction
    save_filters(organization_id, "photos", %{sort_by: sort_by, sort_direction: sort_direction})

    socket
    |> assign(sort_by: sort_by)
    |> assign(sort_direction: sort_direction)
    |> assign_photos(@per_page, nil, true)
    |> noreply()
  end

  def handle_event(
        "toggle_sort_direction",
        _,
        %{
          assigns: %{
            sort_direction: sort_direction,
            current_user: %{organization_id: organization_id}
          }
        } = socket
      ) do
    sort_direction = if(sort_direction == "asc", do: "desc", else: "asc")
    save_filters(organization_id, "photos", %{sort_direction: sort_direction})

    socket
    |> assign(sort_direction: sort_direction)
    |> assign_photos(@per_page, nil, true)
    |> noreply()
  end

  def handle_event(
        "add_album_popup",
        %{},
        %{
          assigns: %{
            gallery: gallery,
            selected_photos: selected_photos,
            client_liked_album: client_liked_album
          }
        } = socket
      ) do
    socket
    |> open_modal(AlbumSettings, %{
      gallery_id: gallery.id,
      selected_photos: selected_photos,
      is_redirect: !client_liked_album
    })
    |> noreply()
  end

  def handle_event(
        "assign_to_album_popup",
        %{},
        %{
          assigns: %{
            gallery: gallery,
            selected_photos: selected_photos,
            photos: photos
          }
        } = socket
      ) do
    dropdown_items =
      gallery
      |> Repo.preload(:albums)
      |> Map.get(:albums)
      |> then(fn albums ->
        case selected_photos do
          [photo_id] ->
            photo = Enum.find(photos, &(&1.id == photo_id))
            Enum.reject(albums, &(&1.id == photo.album_id))

          _ ->
            albums
        end
      end)
      |> Enum.map(&{&1.name, &1.id})

    opts = [
      event: "assign_to_album",
      title: "Assign to album",
      confirm_label: "Save changes",
      close_label: "Cancel",
      subtitle:
        "If you'd like, you can reassign all the selected photos from their  current locations to a
          new album of your choice",
      dropdown?: true,
      dropdown_label: "Assign to which album?",
      dropdown_items: dropdown_items
    ]

    socket
    |> make_popup(opts)
  end

  @impl true
  def handle_event(
        "edit_album_thumbnail_popup",
        _,
        %{
          assigns: %{
            gallery: gallery,
            album: album
          }
        } = socket
      ) do
    socket
    |> open_modal(AlbumThumbnail, %{album_id: album.id, gallery_id: gallery.id})
    |> noreply()
  end

  def handle_event(
        "set_album_thumbnail_popup",
        %{"photo_id" => photo_id},
        %{assigns: %{album: album}} = socket
      ) do
    opts = [
      event: "set_album_thumbnail",
      title: "Set as album thumbnail?",
      subtitle: "Are you sure you wish to set this photo as the thumbnail for #{album.name}?",
      confirm_label: "Yes, set as thumbnail",
      confirm_class: "btn-settings",
      icon: nil,
      payload: %{photo_id: photo_id}
    ]

    socket
    |> make_popup(opts)
  end

  def handle_event(
        "album_settings_popup",
        _,
        %{
          assigns: %{
            gallery: gallery,
            album: album,
            orders: orders
          }
        } = socket
      ) do
    socket
    |> open_modal(AlbumSettings, %{
      gallery_id: gallery.id,
      album: album,
      target: self(),
      has_order?: Enum.any?(orders)
    })
    |> noreply()
  end

  def handle_event(
        "downlaod_photos",
        _,
        %{
          assigns: %{
            gallery: gallery,
            selected_photos: selected_photos,
            current_user: current_user
          }
        } = socket
      ) do
    UserNotifier.deliver_download_start_notification(current_user, gallery)
    Galleries.pack(gallery, selected_photos, user_email: current_user.email)

    socket
    |> push_event("select_mode", %{"mode" => "selected_none"})
    |> assign(:select_mode, "selected_none")
    |> assign(:selected_photos, [])
    |> put_flash(
      :success,
      "Download request sent at #{current_user.email}! The ZIP file with your images is on the way to your inbox"
    )
    |> noreply()
  end

  @impl true
  def handle_event("upload-failed", _, socket) do
    socket
    |> open_modal(UploadError, socket.assigns)
    |> noreply
  end

  @impl true
  def handle_event("re-upload", _, %{assigns: assigns} = socket) do
    socket
    |> open_modal(CloudError, assigns)
    |> noreply
  end

  def handle_event(
        "photo_view",
        %{"photo_id" => photo_id},
        %{assigns: %{photo_ids: photo_ids}} = socket
      ) do
    photo_ids = Enum.reject(photo_ids, &is_binary(&1))

    socket
    |> open_modal(
      PhotoView,
      %{
        photo_id: photo_id,
        from: :photographer,
        is_proofing: false,
        photo_ids:
          photo_ids
          |> CLL.init()
          |> CLL.next(Enum.find_index(photo_ids, &(&1 == photo_id)) || 0)
      }
    )
    |> noreply
  end

  def handle_event(
        "photo_preview_pop",
        %{"photo_id" => photo_id},
        %{
          assigns: %{
            gallery: gallery
          }
        } = socket
      ) do
    socket
    |> open_modal(
      PhotoPreview,
      %{
        gallery: gallery,
        photo_id: photo_id
      }
    )
    |> noreply
  end

  def handle_event(
        "move_to_album_popup",
        %{"album_id" => album_id},
        %{
          assigns: %{
            gallery: gallery,
            selected_photos: selected_photos
          }
        } = socket
      ) do
    [album | _] =
      gallery.albums |> Enum.filter(fn %{id: id} -> id == String.to_integer(album_id) end)

    opts = [
      event: "move_to_album",
      title: "Move to album?",
      confirm_label: "Yes, move #{ngettext("photo", "photos", Enum.count(selected_photos))}",
      subtitle:
        "Are you sure you wish to move the selected #{ngettext("photo", "photos", Enum.count(selected_photos))} to #{album.name}?",
      payload: %{album_id: album_id}
    ]

    socket
    |> make_popup(opts)
  end

  def handle_event(
        "remove_from_album_popup",
        %{"photo_id" => photo_id},
        %{assigns: %{album: album, selected_photos: selected_photos}} = socket
      ) do
    ids =
      if Enum.empty?(selected_photos) do
        [photo_id]
      else
        selected_photos
      end

    opts = [
      event: "remove_from_album",
      title: "Remove from album?",
      confirm_label: "Yes, remove",
      subtitle:
        "Are you sure you wish to remove #{ngettext("this photo", "these photos", Enum.count(ids))} from #{album.name}?",
      payload: %{photo_id: ids}
    ]

    socket
    |> make_popup(opts)
  end

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
  def handle_event(
        "toggle_selections",
        _,
        %{
          assigns: %{selection_filter: selection_filter}
        } = socket
      ) do
    socket
    |> push_event("select_mode", %{"mode" => "selected_none"})
    |> assign(
      selected_photos: [],
      select_mode: "selected_none",
      selection_filter: !selection_filter,
      page: 0
    )
    |> assign_photos(@per_page, nil, true)
    |> noreply()
  end

  def handle_event("toggle_favorites", _, socket) do
    socket
    |> assign(:selected_photos, [])
    |> assign(:inprogress_photos, [])
    |> push_event("select_mode", %{"mode" => "selected_none"})
    |> assign(:select_mode, "selected_none")
    |> toggle_photographer_favorites(@per_page)
  end

  def handle_event(
        "update_photo_position",
        %{"photo_id" => photo_id, "type" => type, "args" => args},
        %{
          assigns: %{
            gallery: %{
              id: gallery_id
            },
            current_user: %{organization_id: organization_id}
          }
        } = socket
      ) do
    Galleries.update_gallery_photo_position(
      gallery_id,
      photo_id
      |> String.to_integer(),
      type,
      args
    )

    PositionNormalizer.normalize(gallery_id)

    case PreferredFilter.load_preferred_filters(organization_id, "photos") do
      nil ->
        noreply(socket)

      filter ->
        Repo.delete(filter)

        socket
        |> assign(sort_by: "none")
        |> noreply()
    end
  end

  def handle_event(
        "update_photo_position",
        false,
        socket
      ) do
    noreply(socket)
  end

  def handle_event(
        "delete_photo_popup",
        %{"photo_id" => photo_id},
        %{
          assigns: %{
            gallery: %{
              id: gallery_id
            }
          }
        } = socket
      ) do
    opts = [
      event: "delete_photo",
      title: "Delete this photo?",
      subtitle:
        "Are you sure you wish to permanently delete this photo from #{socket.assigns.gallery.name} ?",
      purchased: Cart.digital_purchased?(%{id: gallery_id}, %{id: photo_id}),
      replace_event: "replace_purchased_photo_popup",
      payload: %{photo_id: photo_id, gallery_id: gallery_id}
    ]

    socket
    |> make_popup(opts)
  end

  def handle_event("delete_selected_photos_popup", _, socket) do
    opts = [
      event: "delete_selected_photos",
      title: "Delete selected photos?",
      subtitle:
        "Are you sure you wish to permanently delete selected photos from #{socket.assigns.gallery.name} ?"
    ]

    socket
    |> make_popup(opts)
  end

  def handle_event(
        "selected_all",
        _,
        %{
          assigns:
            %{
              gallery: gallery,
              current_user: %{organization: organization}
            } = assigns
        } = socket
      ) do
    selection_filter = assigns[:selection_filter] || false
    album = assigns[:album] || nil

    photo_ids =
      if selection_filter && album do
        Orders.get_proofing_order_photos(album.id, organization.id)
        |> Enum.flat_map(fn %{digitals: digitals} ->
          Enum.map(digitals, & &1.photo.id)
        end)
      else
        Galleries.get_gallery_photo_ids(gallery.id, make_opts(socket, @per_page))
      end

    socket
    |> push_event("select_mode", %{"mode" => "selected_all"})
    |> assign(:selected_photos, photo_ids)
    |> assign(:select_mode, "selected_all")
    |> noreply
  end

  def handle_event("selected_none", _, socket) do
    socket
    |> then(fn
      %{
        assigns: %{
          photographer_favorites_filter: true
        }
      } = socket ->
        socket
        |> assign(:page, 0)
        |> assign(:photographer_favorites_filter, false)
        |> assign_photos(@per_page, nil, true)

      socket ->
        socket
    end)
    |> push_event("select_mode", %{"mode" => "selected_none"})
    |> assign(:select_mode, "selected_none")
    |> assign(:selected_photos, [])
    |> noreply
  end

  def handle_event(
        "selected_favorite",
        _,
        %{
          assigns: %{
            gallery: gallery
          }
        } = socket
      ) do
    socket
    |> assign(:page, 0)
    |> assign(:photographer_favorites_filter, true)
    |> then(fn socket ->
      photo_ids = Galleries.get_gallery_photo_ids(gallery.id, make_opts(socket, @per_page))

      socket
      |> assign(:selected_photos, photo_ids)
    end)
    |> push_event("select_mode", %{"mode" => "selected_favorite"})
    |> assign(:select_mode, "selected_favorite")
    |> assign_photos(@per_page, nil, true)
    |> noreply
  end

  @impl true
  def handle_event(
        "toggle_selected_photos",
        %{"photo_id" => photo_id},
        %{
          assigns: %{
            selected_photos: selected_photos,
            orders: orders
          }
        } = socket
      ) do
    photo_id = String.to_integer(photo_id)

    order_photo_ids =
      case orders do
        [] ->
          []

        orders ->
          Enum.flat_map(orders, fn %{digitals: digitals} ->
            Enum.map(digitals, & &1.photo.id)
          end)
      end

    selected_photos =
      if Enum.member?(order_photo_ids, photo_id) do
        selected_photos
      else
        if Enum.member?(selected_photos, photo_id) do
          List.delete(selected_photos, photo_id)
        else
          [photo_id | selected_photos]
        end
      end

    socket
    |> assign(:selected_photos, selected_photos)
    |> noreply()
  end

  def handle_event(
        "folder-information",
        %{"folder" => folder, "sub_folders" => sub_folders},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    socket
    |> open_modal(FolderUpload, %{folder: folder, sub_folders: sub_folders, gallery: gallery})
    |> noreply()
  end

  def handle_event("remove-uploading", _, socket) do
    socket
    |> push_event("remove-uploading", %{})
    |> noreply()
  end

  @impl true
  defdelegate handle_event(event, params, socket), to: TodoplaceWeb.GalleryLive.Shared

  @impl true
  def handle_info({:album_settings, %{message: message, album: album}}, socket) do
    socket
    |> close_modal()
    |> assign(:album, album |> Repo.preload(:photos))
    |> put_flash(:success, message)
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "delete_photo", %{photo_id: photo_id}},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    updated_socket = delete_photos_multi(socket, [photo_id])

    if Cart.digital_purchased?(gallery, %{id: photo_id}) do
      %{order: order} =
        Cart.digital_purchased_query(gallery.id, [photo_id])
        |> Repo.one!()
        |> Repo.preload(:order)

      {:ok, _} = PackDigitals.enqueue(order)
    end

    updated_socket
    |> close_modal()
    |> noreply
  end

  def handle_info(
        {:confirm_event, "replace_purchased_photo_popup", %{photo_id: photo_id}},
        %{assigns: %{gallery: %{id: gallery_id}}} = socket
      ) do
    socket
    |> open_modal(
      EditProduct,
      %{
        photo_id: photo_id,
        gallery_id: gallery_id,
        description: "Select one of your gallery photos to replace the already purchased photo",
        page_title: "Replace Photo ",
        parent_pid: self()
      }
    )
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "replace_purchased_photo",
         %{new_photo_id: new_photo_id, old_photo_id: old_photo_id}},
        %{assigns: %{gallery: %{id: gallery_id}}} = socket
      ) do
    with {:ok, false} <- {:ok, new_photo_id == old_photo_id},
         {:ok, %{order: order}} <-
           Orders.update_digital_photo(gallery_id, old_photo_id, new_photo_id) do
      {:ok, _} = PackDigitals.enqueue(order)

      socket
      |> delete_photos_multi([old_photo_id], "replaced successfully", "replace photo")
    else
      {:ok, true} ->
        socket
        |> put_flash(:success, "Photo Replaced")

      _ ->
        socket
        |> put_flash(:error, "Failed to replace purchased photo")
    end
    |> close_modal()
    |> noreply
  end

  def handle_info(
        {:confirm_event, "delete_selected_photos", _},
        %{assigns: %{gallery: %{id: gallery_id}, selected_photos: selected_photos}} = socket
      ) do
    updated_socket = delete_photos_multi(socket, selected_photos)

    Cart.digital_purchased_query(gallery_id, selected_photos, :order)
    |> Repo.all()
    |> Enum.each(fn order ->
      {:ok, _} = PackDigitals.enqueue(order)
    end)

    updated_socket
    |> close_modal()
    |> noreply
  end

  def handle_info(
        {:confirm_event, "delete_album", %{album_id: album_id}},
        %{assigns: %{gallery: %{id: gallery_id}}} = socket
      ) do
    album_id
    |> Albums.get_album!()
    |> Galleries.delete_album()
    |> case do
      {:ok, _album} ->
        gallery_id
        |> Albums.get_albums_by_gallery_id()
        |> case do
          [] ->
            ~p"/galleries/#{gallery_id}/photos"

          _ ->
            ~p"/galleries/#{gallery_id}/albums"
        end
        |> then(&push_redirect(socket, to: &1))
        |> put_flash(:success, "Album deleted successfully")

      _any ->
        socket
        |> put_flash(:success, "Could not delete album")
    end
    |> close_modal()
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "remove_from_album", %{photo_id: ids}},
        %{
          assigns: %{
            album: album,
            gallery: gallery,
            total_progress: total_progress
          }
        } = socket
      ) do
    {:ok, _} = Galleries.remove_photos_from_album(ids, gallery.id)

    send_update(SideNavComponent,
      id: gallery.id,
      gallery: gallery,
      total_progress: total_progress
    )

    socket
    |> close_modal()
    |> assign(:selected_photos, [])
    |> push_event("remove_items", %{"ids" => ids})
    |> assign_photos(@per_page, nil, true)
    |> put_flash(:success, remove_from_album_success_message(ids, album))
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "move_to_album", %{album_id: album_id}},
        %{
          assigns: %{
            selected_photos: selected_photos,
            gallery: gallery,
            total_progress: total_progress
          }
        } = socket
      ) do
    album = Albums.get_album!(album_id)

    selected_photos =
      if album.is_finals do
        selected_photos
      else
        duplicate_photo_ids =
          Galleries.get_selected_photos_name(selected_photos)
          |> Galleries.filter_duplication(album_id)

        Galleries.delete_photos_by(duplicate_photo_ids)

        selected_photos -- duplicate_photo_ids
      end

    Galleries.move_to_album(String.to_integer(album_id), selected_photos)

    if album.is_proofing && is_nil(gallery.watermark) do
      %{job: %{client: %{organization: %{name: name}}}} = Galleries.populate_organization(gallery)

      gallery
      |> Galleries.get_photos_by_ids(selected_photos)
      |> Enum.each(&ProcessingManager.start(&1, Watermark.build(name, gallery)))
    end

    Galleries.sort_album_photo_positions_by_name(String.to_integer(album_id))

    send_update(SideNavComponent,
      id: gallery.id,
      gallery: gallery,
      total_progress: total_progress
    )

    socket
    |> close_modal()
    |> assign(:selected_photos, [])
    |> assign_photos(@per_page, nil, true)
    |> put_flash(
      :success,
      move_to_album_success_message(selected_photos, album_id, gallery)
    )
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "set_album_thumbnail", %{photo_id: photo_id}},
        %{
          assigns: %{
            album: album
          }
        } = socket
      ) do
    thumbnail = Galleries.get_photo(String.to_integer(photo_id))

    {:ok, _} =
      album
      |> Repo.preload([:photos, :thumbnail_photo])
      |> Albums.save_thumbnail(thumbnail)

    socket
    |> close_modal()
    |> put_flash(:success, "Album thumbnail successfully updated")
    |> noreply()
  end

  def handle_info(
        {:photo_processed, _, photo},
        socket
      ) do
    socket
    |> stream_insert(:photos_new, photo)
    |> assign_invalid_preview_images()
    |> noreply()
  end

  def handle_info(
        {:photo_insert, photo},
        %{assigns: %{photo_ids: photo_ids}} = socket
      ) do
    socket
    |> assign_photos(@per_page)
    |> assign(:photo_ids, photo_ids ++ [photo.id])
    |> noreply()
  end

  def handle_info(
        {:photos_stream, %{id: id, name: name}},
        %{assigns: %{photo_ids: photo_ids}} = socket
      ) do
    socket
    |> stream_insert(
      :photos_new,
      %{
        id: id,
        uuid: id,
        name: name,
        done?: false,
        error: nil,
        preview_url: nil,
        watermarked_preview_url: nil
      }
    )
    |> assign(:photo_ids, [id | photo_ids])
    |> noreply()
  end

  def handle_info(
        {:gallery_progress, %{total_progress: total_progress}},
        socket
      ) do
    socket
    |> assign(:total_progress, total_progress)
    |> assign(
      :show_upload_remover?,
      case total_progress do
        100 -> false
        _ -> true
      end
    )
    |> noreply()
  end

  def handle_info(
        {:uploading, %{pid: pid, uploading: true}},
        %{assigns: %{current_user: user, gallery: gallery}} = socket
      ) do
    remove_cache(user.id, gallery.id)
    add_cache(socket, pid)

    socket
    |> noreply()
  end

  def handle_info({:uploading, %{success_message: success_message}}, socket) do
    socket
    |> assign_photos(@per_page)
    |> put_flash(:success, success_message)
    |> noreply()
  end

  def handle_info(:clear_photos_error, socket) do
    socket
    |> assign(:photos_error_count, 0)
    |> noreply()
  end

  def handle_info({:total_progress, total_progress}, socket) do
    socket |> assign(:total_progress, total_progress) |> noreply()
  end

  def handle_info(
        {:photos_error,
         %{
           invalid_photos: invalid_photos,
           pending_photos: pending_photos,
           photos_error_count: photos_error_count
         }},
        socket
      ) do
    socket
    |> assign(:invalid_photos, invalid_photos)
    |> assign(:pending_photos, pending_photos)
    |> assign(:photos_error_count, photos_error_count)
    |> noreply()
  end

  def handle_info(:photo_upload_completed, socket) do
    socket
    |> assign_photos(@per_page, nil, true)
    |> noreply()
  end

  def handle_info({:upload_success_message, success_message}, socket) do
    socket |> put_flash(:success, success_message) |> noreply()
  end

  def handle_info({:save, %{message: message}}, socket) do
    socket
    |> close_modal()
    |> put_flash(:success, message)
    |> assign_photos(@per_page)
    |> noreply()
  end

  def handle_info({:message_composed, message_changeset, recipients}, socket) do
    add_message_and_notify(socket, message_changeset, recipients, "gallery")
  end

  @impl true
  def handle_info({:message_composed_for_album, message_changeset, recipients}, socket) do
    add_message_and_notify(socket, message_changeset, recipients, "album")
  end

  def handle_info({:pack, _, _}, socket), do: noreply(socket)

  def handle_info(
        {
          :confirm_event,
          "assign_to_album",
          %{item_id: item_id}
        },
        %{assigns: %{gallery: %{albums: albums}}} = socket
      ) do
    album = Enum.find(albums, &(to_string(&1.id) == item_id))

    opts = [
      event: "assign_album_confirmation",
      title: "Move photo",
      subtitle: "Are you sure you wish to to move selected photos from its current location to
            #{album.name} ?",
      confirm_label: "Yes, move",
      payload: %{album_id: album.id}
    ]

    socket
    |> make_popup(opts)
  end

  def handle_info(
        {
          :confirm_event,
          "add_from_clients_favorite",
          %{album: album} = params
        },
        socket
      ) do
    create_album(album, params, socket)
  end

  def handle_info(
        {
          :confirm_event,
          "assign_album_confirmation",
          %{album_id: album_id}
        },
        %{assigns: %{selected_photos: selected_photos, gallery: %{albums: albums}}} = socket
      ) do
    album = Enum.find(albums, &(&1.id == album_id))
    Galleries.move_to_album(album_id, selected_photos)

    socket
    |> put_flash(:success, "Photos successfully moved to #{album.name}")
    |> close_modal()
    |> noreply()
  end

  def handle_info(:update_photo_gallery_state, socket) do
    socket
    |> assign_show_favorite_toggle()
    |> process_favorites(@per_page)
  end

  def handle_info({:update_photo_liked, photo}, socket) do
    socket
    |> assign_show_favorite_toggle()
    |> stream_insert(:photos_new, photo)
    |> noreply()
  end

  @re_call_time 5000
  def handle_info(:invalid_preview, socket) do
    Process.send_after(self(), :invalid_preview, @re_call_time)

    socket
    |> assign_invalid_preview_images
    |> noreply()
  end

  def handle_info({:processing_message, show?}, socket) do
    socket
    |> assign(:processing_message?, show?)
    |> noreply()
  end

  def handle_info({:remove_uploading, ids}, socket) do
    ids
    |> Enum.reduce(socket, fn id, socket ->
      socket
      |> stream_delete_by_dom_id(:photos_new, "photos_new-#{id}")
    end)
    |> assign(:total_progress, 0)
    |> assign(:show_upload_remover?, false)
    |> noreply()
  end

  defp assign_invalid_preview_images(%{assigns: %{gallery: gallery}} = socket) do
    invalid_preview_photos = Galleries.get_gallery_photos(gallery.id, invalid_preview: true)

    socket
    |> assign(invalid_preview_photos: invalid_preview_photos)
  end

  defp assigns(
         %{assigns: %{current_user: %{organization_id: organization_id}}} = socket,
         gallery_id,
         album \\ nil
       ) do
    gallery = get_gallery!(gallery_id)

    if connected?(socket) do
      Galleries.subscribe(gallery)
      PubSub.subscribe(Todoplace.PubSub, "clear_photos_error:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "photo_uploaded:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "uploading:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "invalid_preview:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "photo_insert:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "photos_stream:#{gallery_id}")
      PubSub.subscribe(Todoplace.PubSub, "processing_message:#{gallery_id}")

      send(self(), :invalid_preview)
    end

    currency = Todoplace.Currency.for_gallery(gallery)

    socket
    |> assign(
      favorites_count: Galleries.gallery_favorites_count(gallery),
      show_products: currency in Utils.products_currency(),
      gallery: gallery,
      album: album,
      page_title: page_title(socket.assigns.live_action),
      products: Galleries.products(gallery),
      invalid_preview_photos: [],
      processing_message?: false
    )
    |> assign_gallery_preferred_filters(organization_id)
    |> assign_photos(@per_page)
    |> assign_show_favorite_toggle()
    |> noreply()
  end

  defp assign_show_favorite_toggle(%{assigns: %{gallery: %{id: id}} = assigns} = socket) do
    opts =
      assigns
      |> Map.get(:album)
      |> photos_album_opts()
      |> Keyword.put(:photographer_favorites_filter, true)

    show_favorite_toggle = Galleries.get_gallery_photos(id, opts) |> Enum.count() > 0

    assign(socket, show_favorite_toggle: show_favorite_toggle)
  end

  defp maybe_has_selected_photo({:noreply, socket}, params) do
    params
    |> case do
      %{"go_to_original" => "true", "photo_id" => photo_id} ->
        photo_id = String.to_integer(photo_id)

        socket
        |> assign(:selected_photos, [photo_id])
        |> assign(:selected_photo_id, photo_id)

      _ ->
        socket
    end
    |> noreply()
  end

  defp delete_photos_multi(
         %{assigns: %{gallery: %{id: gallery_id}}} = socket,
         selected_photos,
         msg \\ "deleted successfully",
         error_msg \\ "delete photos"
       ) do
    %{total_count: total_count} = gallery = get_gallery!(gallery_id)

    Multi.new()
    |> Multi.run(:delete_photos, fn _, _ -> Galleries.delete_photos(selected_photos) end)
    |> Multi.run(:update_gallery, fn _, %{delete_photos: {count, _}} ->
      Galleries.update_gallery(gallery, %{total_count: total_count - count})
    end)
    |> Repo.transaction()
    |> then(fn
      {:ok, %{update_gallery: gallery, delete_photos: {count, _}}} ->
        socket
        |> assign(:gallery, gallery)
        |> assign(:selected_photos, [])
        |> assign_invalid_preview_images()
        |> put_flash(
          :success,
          "#{count} #{ngettext("photo", "photos", count)} #{msg}"
        )
        |> assign_photos(@per_page, nil, true)

      {:error, _} ->
        put_flash(socket, :error, "Could not #{error_msg}")
    end)
  end

  defp move_to_album_success_message(selected_photos, album_id, %{albums: albums}) do
    album = Enum.find(albums, &(to_string(&1.id) == album_id))

    photos_count = length(selected_photos)

    "#{photos_count} #{ngettext("photo", "photos", photos_count)} successfully moved to #{album.name}"
  end

  def select_dropdown(assigns) do
    assigns =
      assigns
      |> Enum.into(%{class: ""})

    ~H"""
    <div class="flex flex-col w-full lg:w-auto mr-2">
      <div class="font-extrabold text-sm flex flex-col whitespace-nowrap mb-1"><%= @title %></div>
      <div class="flex">
        <div
          id={@id}
          class={
            classes("relative w-32 border-grey border p-2 cursor-pointer", %{
              "lg:w-64" => @id == "status" and @type == "lead",
              "rounded-l-lg" => @id == "sort_by",
              "rounded-lg" => @title == "Filter" or @id != "sort_by"
            })
          }
          data-offset-y=""
          phx-hook="Select"
        >
          <div {testid("dropdown_#{@id}")} class="flex flex-row items-center border-gray-700">
            <%= capitalize_per_word(String.replace(@selected_option, "_", " ")) %>
            <.icon name="down" class="w-3 h-3 ml-auto lg:mr-2 mr-1 stroke-current stroke-2 open-icon" />
            <.icon
              name="up"
              class="hidden w-3 h-3 ml-auto lg:mr-2 mr-1 stroke-current stroke-2 close-icon"
            />
          </div>
          <ul class={"absolute w-32 z-30 hidden mt-2 bg-white toggle rounded-md popover-content border border-base-200 #{@class}"}>
            <%= for option <- @options_list do %>
              <li
                id={option.id}
                target-class="toggle-it"
                parent-class="toggle"
                toggle-type="selected-active"
                phx-hook="ToggleSiblings"
                class="flex items-center py-1.5 hover:bg-blue-planning-100 hover:rounded-md"
                phx-click={"apply_filter_#{@id}"}
                phx-value-option={option.id}
              >
                <button
                  id={"btn-#{option.id}"}
                  class={
                    classes("album-select", %{"w-64" => @id == "status", "w-40" => @id != "status"})
                  }
                >
                  <%= option.title %>
                </button>
                <%= if option.id == @selected_option do %>
                  <.icon name="tick" class="w-6 h-5 ml-auto mr-1 toggle-it text-green" />
                <% end %>
              </li>
            <% end %>
          </ul>
        </div>
        <%= if @title == "Sort by" do %>
          <div class="items-center flex border rounded-r-lg border-grey p-2">
            <button phx-click="toggle_sort_direction" disabled={@selected_option not in ["filename"]}>
              <%= if @sort_direction == "asc" do %>
                <.icon
                  name="sort-vector-2"
                  {testid("edit-link-button")}
                  class={
                    classes("blue-planning-300 w-5 h-5", %{
                      "pointer-events-none opacity-40" => @selected_option not in ["filename"]
                    })
                  }
                />
              <% else %>
                <.icon
                  name="sort-vector"
                  {testid("edit-link-button")}
                  class={
                    classes("blue-planning-300 w-5 h-5", %{
                      "pointer-events-none opacity-40" => @selected_option not in ["filename"]
                    })
                  }
                />
              <% end %>
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp sort_options() do
    [
      %{title: "None", id: "none", column: "none", direction: "desc"},
      %{title: "Filename", id: "filename", column: "name", direction: "asc"}
    ]
  end

  defp capitalize_per_word(string) do
    String.split(string)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp remove_from_album_success_message(selected_photos, album) do
    photos_count = length(selected_photos)

    "#{photos_count} #{ngettext("photo", "photos", photos_count)} successfully removed from #{album.name}"
  end

  defp options(album) do
    [%{title: "All", id: "selected_all"}] ++
      if album && album.is_proofing do
        [%{title: "None", id: "selected_none"}]
      else
        [%{title: "Favorite", id: "selected_favorite"}, %{title: "None", id: "selected_none"}]
      end
  end

  defp page_title(:index), do: "Photos"
  defp page_title(:edit), do: "Edit Photos"
  defp page_title(:upload), do: "New Photos"

  defp extract_album(album, album_return, other \\ nil) do
    if album, do: Map.get(album, album_return), else: other
  end

  defp proofing_album_hash(album, socket) do
    album = Albums.set_album_hash(album)
    ~p"/album/#{album.client_link_hash}"
  end

  defp truncate(string) do
    case get_class(string) do
      "tooltip" ->
        String.slice(string, 0..@string_length) <> "..."

      _ ->
        string
    end
  end

  defp get_class(string), do: if(String.length(string) > @string_length, do: "tooltip")

  defp add_cache(%{assigns: %{current_user: user, gallery: gallery}}, pid) do
    upload_data = TodoplaceWeb.UploaderCache.get(user.id)
    gallery_ids = upload_data |> Enum.map(fn {_, gallery_id, _} -> gallery_id end)

    if gallery.id not in gallery_ids do
      TodoplaceWeb.UploaderCache.put(user.id, [{pid, gallery.id, 0} | upload_data])
    end
  end

  defp album_actions(assigns) do
    assigns = assigns |> Enum.into(%{exclude_album_id: nil})

    ~H"""
    <%= for album <- @albums do %>
      <%= if @exclude_album_id != album.id && @exclude_album_id != "client_liked" do %>
        <li class={"relative py-1 hover:bg-blue-planning-100 hover:rounded-md #{get_class(album.name)}"}>
          <button class="album-actions" phx-click="move_to_album_popup" phx-value-album_id={album.id}>
            Move to <%= truncate(album.name) %>
          </button>
          <div class="cursor-default tooltiptext">Move to <%= album.name %></div>
        </li>
      <% end %>
    <% end %>
    """
  end

  defdelegate handle_info(params, socket), to: GalleryLive.Shared
end
