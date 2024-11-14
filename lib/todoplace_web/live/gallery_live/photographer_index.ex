defmodule TodoplaceWeb.GalleryLive.PhotographerIndex do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "live_photographer"]

  import TodoplaceWeb.LiveHelpers

  import TodoplaceWeb.GalleryLive.Shared
  import TodoplaceWeb.Shared.StickyUpload, only: [sticky_upload: 1]
  import TodoplaceWeb.Live.Shared, only: [make_popup: 2, serialize: 1]

  alias Todoplace.{Repo, Galleries, Messages, Notifiers.ClientNotifier}
  alias TodoplaceWeb.{Shared.ConfirmationComponent, GalleryLive.Shared}

  alias TodoplaceWeb.GalleryLive.{
    Settings.CustomWatermarkComponent
  }

  alias Galleries.{
    CoverPhoto,
    Workers.PhotoStorage,
    PhotoProcessing.ProcessingManager,
    PhotoProcessing.Waiter
  }

  @upload_options [
    accept: ~w(.jpg .jpeg .png image/jpeg image/png),
    max_entries: 1,
    max_file_size: String.to_integer(Application.compile_env(:todoplace, :photo_max_file_size)),
    auto_upload: true,
    external: &__MODULE__.presign_cover_entry/2,
    progress: &__MODULE__.handle_cover_progress/3
  ]
  @bucket Application.compile_env(:todoplace, :photo_storage_bucket)

  @impl true
  def mount(_params, _session, %{assigns: %{current_user: user}} = socket) do
    socket
    |> assign(:upload_bucket, @bucket)
    |> assign(:total_progress, 0)
    |> assign(:photos_error_count, 0)
    |> assign(:cover_photo_processing, false)
    |> assign(:user, user)
    |> allow_upload(:cover_photo, @upload_options)
    |> assign(:password_toggle, false)
    |> ok()
  end

  @impl true
  def handle_params(%{"id" => id} = params, _, socket) do
    Phoenix.PubSub.subscribe(Todoplace.PubSub, "gallery:#{id}")

    gallery = fetch_gallery!(id)

    prepare_gallery(gallery)

    socket
    |> is_mobile(params)
    |> assign(:has_order?, Todoplace.Orders.placed_orders_count(gallery) > 0)
    |> assign(:gallery, gallery)
    |> noreply()
  end

  @impl true
  def handle_event("start", _params, socket) do
    socket.assigns.uploads.cover_photo
    |> case do
      %{valid?: false, ref: ref} ->
        {:noreply, cancel_upload(socket, :cover_photo, ref)}

      _ ->
        socket |> noreply()
    end
  end

  @impl true
  def handle_event(
        "delete_cover_photo_popup",
        _,
        %{
          assigns: %{
            gallery: gallery
          }
        } = socket
      ) do
    socket
    |> ConfirmationComponent.open(%{
      close_label: "Cancel",
      confirm_event: "delete_cover_photo",
      confirm_label: "Yes, delete",
      icon: "warning-orange",
      class: "dialog-photographer",
      title: "Delete this photo?",
      subtitle: "Are you sure you wish to permanently delete this photo from #{gallery.name} ?"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "delete_gallery_popup",
        _,
        %{
          assigns: %{
            gallery: gallery
          }
        } = socket
      ) do
    socket
    |> ConfirmationComponent.open(%{
      close_label: "Cancel",
      close_class: "delete_btn",
      confirm_event: "delete_gallery",
      confirm_label: "Yes, delete",
      class: "dialog-photographer",
      icon: "warning-orange",
      title: "Delete Gallery?",
      gallery_name: gallery.name,
      gallery_count: gallery.total_count
    })
    |> noreply()
  end

  @impl true
  def handle_event("delete_watermark_popup", _, socket) do
    opts = [
      event: "delete_watermark",
      title: "Delete watermark?",
      subtitle: "Are you sure you wish to permanently delete your
      custom watermark? You can always add another
      one later."
    ]

    make_popup(socket, opts)
  end

  @impl true
  def handle_event("watermark_popup", _, socket) do
    send(self(), :open_modal)
    socket |> noreply()
  end

  @impl true
  def handle_event("back_to_navbar", _, %{assigns: %{is_mobile: is_mobile}} = socket) do
    socket |> assign(:is_mobile, !is_mobile) |> noreply
  end

  @impl true
  def handle_event("disable_gallery_popup", _, socket) do
    opts = [
      event: "disable_gallery",
      title: "Disable Orders?",
      confirm_label: "Yes, disable orders",
      subtitle:
        "If you disable orders, the gallery will remain intact, but you won’t be able to update it anymore. Your client will still be able to view the gallery."
    ]

    make_popup(socket, opts)
  end

  @impl true
  def handle_event("enable_gallery_popup", _, socket) do
    opts = [
      event: "enable_gallery",
      title: "Enable Orders?",
      confirm_label: "Yes, enable orders",
      subtitle:
        "If you enable the gallery, your clients will be able to make additional gallery purchases moving forward."
    ]

    make_popup(socket, opts)
  end

  @impl true
  def handle_info(
        {:message_composed, message_changeset, recipients},
        %{
          assigns: %{
            job: job,
            gallery: gallery,
            current_user: user
          }
        } = socket
      ) do
    %{id: oban_job_id} =
      %{
        message: serialize(message_changeset),
        job_id: job.id,
        recipients: recipients,
        user: serialize(%{organization_id: user.organization_id})
      }
      |> Todoplace.Workers.ScheduleEmail.new(schedule_in: 900)
      |> Oban.insert!()

    Waiter.postpone(gallery.id, fn ->
      Oban.cancel_job(oban_job_id)

      {:ok, %{client_message: message, client_message_recipients: _}} =
        Messages.add_message_to_job(message_changeset, job, recipients, user)
        |> Repo.transaction()

      ClientNotifier.deliver_email(message, recipients)
      Galleries.update_gallery(gallery, %{gallery_send_at: DateTime.utc_now()})
    end)

    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Email sent",
      subtitle: "Yay! Your email has been successfully sent"
    })
    |> noreply()
  end

  @impl true
  def handle_info({:message_composed_for_album, message_changeset, recipients}, socket) do
    add_message_and_notify(socket, message_changeset, recipients, "album")
  end

  @impl true
  def handle_info(:open_modal, %{assigns: %{gallery: gallery}} = socket) do
    socket
    |> open_modal(CustomWatermarkComponent, %{gallery: gallery})
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "delete_watermark", _},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    {:ok, _} = Galleries.delete_gallery_watermark(gallery)
    send(self(), :clear_watermarks)

    socket
    |> close_modal()
    |> preload_watermark()
    |> noreply()
  end

  @impl true
  def handle_info({:uploading, %{success_message: success_message}}, socket) do
    socket |> put_flash(:success, success_message) |> noreply()
  end

  @impl true
  def handle_info({:photo_processed, _, photo}, socket) do
    photo_update =
      %{
        id: photo.id,
        url: preview_url(photo)
      }
      |> Jason.encode!()

    socket
    |> assign(:photo_updates, photo_update)
    |> noreply()
  end

  @impl true
  def handle_info({:gallery_progress, %{total_progress: total_progress}}, socket) do
    socket
    |> assign(:total_progress, if(total_progress == 0, do: 1, else: total_progress))
    |> noreply()
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

  @impl true
  def handle_info(:close_watermark_popup, socket) do
    socket |> close_modal() |> noreply()
  end

  @impl true
  def handle_info(:preload_watermark, socket) do
    socket
    |> preload_watermark()
    |> noreply()
  end

  @impl true
  def handle_info(:clear_watermarks, %{assigns: %{gallery: gallery}} = socket) do
    Galleries.clear_watermarks(gallery.id)
    noreply(socket)
  end

  @impl true
  def handle_info(:expiration_saved, %{assigns: %{gallery: gallery}} = socket) do
    gallery = fetch_gallery!(gallery.id)

    socket
    |> assign(:gallery, gallery)
    |> put_flash(:success, "The expiration date has been successfully updated")
    |> noreply()
  end

  @impl true
  def handle_info(:gallery_password, %{assigns: %{gallery: gallery}} = socket) do
    gallery = fetch_gallery!(gallery.id)

    socket
    |> assign(:gallery, gallery)
    |> noreply()
  end

  def handle_info({:cover_photo_processed, _, _}, %{assigns: %{gallery: gallery}} = socket) do
    gallery = fetch_gallery!(gallery.id)

    socket
    |> assign(:gallery, gallery)
    |> assign(:cover_photo_processing, false)
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "delete_gallery", %{}},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    gallery
    |> Galleries.delete_gallery()
    |> process_gallery(socket, :delete)
  end

  @impl true
  def handle_info(
        {:confirm_event, "delete_cover_photo"},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    socket
    |> assign(
      :gallery,
      Galleries.delete_gallery_cover_photo(gallery) |> Repo.preload(:photographer, job: :client)
    )
    |> close_modal()
    |> noreply()
  end

  @impl true
  def handle_info({:pack, :ok, _}, socket) do
    socket
    |> put_flash(:success, "Gallery is ready for download")
    |> noreply()
  end

  @impl true
  def handle_info({:pack, _, _}, socket), do: noreply(socket)

  @impl true
  def handle_info(
        {:confirm_event, "disable_gallery", _},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    gallery
    |> Galleries.update_gallery(%{status: :disabled})
    |> process_gallery(socket, :disabled)
  end

  @impl true
  def handle_info(
        {:confirm_event, "enable_gallery", _},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    gallery
    |> Galleries.update_gallery(%{status: :active})
    |> process_gallery(socket, :enabled)
  end

  # for validating and saving gallery name
  @impl true
  defdelegate handle_info(message, socket), to: Shared

  defp process_gallery(result, socket, type) do
    {success, failure} =
      case type do
        :delete -> {"deleted", "delete"}
        :enabled -> {"enabled", "enable"}
        _ -> {"disabled", "disable"}
      end

    case result do
      {:ok, gallery} ->
        process_gallery_message(socket, success, gallery)

      _any ->
        socket
        |> put_flash(:error, "Could not #{failure} gallery")
        |> close_modal()
        |> noreply()
    end
  end

  def handle_cover_progress(:cover_photo, entry, %{assigns: %{gallery: gallery}} = socket) do
    if entry.done? do
      gallery.id
      |> CoverPhoto.original_path(entry.uuid)
      |> ProcessingManager.process_cover_photo()
    end

    socket
    |> assign(:cover_photo_processing, true)
    |> noreply
  end

  defp process_gallery_message(socket, type, gallery) do
    case type do
      "deleted" ->
        socket
        |> push_redirect(to: ~p"/jobs/#{gallery.job_id}")
        |> put_flash(:success, "The gallery has been #{type}")
        |> noreply()

      _any ->
        socket
        |> assign(:gallery, gallery)
        |> close_modal()
        |> put_flash(:success, "The gallery has been #{type}")
        |> noreply()
    end
  end

  def presign_cover_entry(entry, %{assigns: %{gallery: gallery}} = socket) do
    key = CoverPhoto.original_path(gallery.id, entry.uuid)

    sign_opts = [
      expires_in: 600,
      bucket: socket.assigns.upload_bucket,
      key: key,
      fields: %{
        "content-type" => entry.client_type,
        "cache-control" => "public, max-age=@upload_options"
      },
      conditions: [
        [
          "content-length-range",
          0,
          String.to_integer(Application.get_env(:todoplace, :photo_max_file_size))
        ]
      ]
    ]

    params = PhotoStorage.params_for_upload(sign_opts)
    meta = %{uploader: "GCS", key: key, url: params[:url], fields: params[:fields]}

    {:ok, meta, socket}
  end

  defp preload_watermark(%{assigns: %{gallery: gallery}} = socket) do
    socket
    |> assign(
      :gallery,
      Galleries.load_watermark_in_gallery(gallery) |> Repo.preload(:photographer, job: :client)
    )
  end

  defp remove_watermark_button(assigns) do
    ~H"""
    <button type="button" disabled={assigns.disabled} title="remove watermark" phx-click="delete_watermark_popup" class="pl-5">
      <.icon name="remove-icon" class={classes("w-3.5 h-3.5 ml-1 text-base-250", %{"pointer-events-none" => assigns.disabled})}/>
    </button>
    """
  end

  defp delete_gallery_section(%{has_order?: has_order?, gallery: gallery} = assigns) do
    if has_order? do
      case disabled?(gallery) do
        true ->
          ~H"""
            <h3 class="font-sans">Enable Gallery</h3>
            <p class="font-sans">
            Gallery orders are disabled, your client has made purchases from this gallery, so you can't delete it, or they'll lose their order
            history. This action will enable additional gallery orders moving forward.
            </p>
            <button {testid("deleteGalleryPopupButton")} phx-click={"enable_gallery_popup"} class="justify-center w-full py-3 font-sans border border-black rounded-lg mt-7" id="deleteGalleryPopupButton">
              Enable gallery
            </button>
          """

        false ->
          ~H"""
            <h3 class="font-sans">Disable Future Gallery Orders</h3>
            <p class="font-sans">
              Your client has made purchases from this gallery. This action will prohibit them from being able to make additional gallery orders moving forward.
            </p>
            <button {testid("deleteGalleryPopupButton")} phx-click={"disable_gallery_popup"} class="justify-center w-full py-3 font-sans border border-black rounded-lg mt-7" id="deleteGalleryPopupButton">
              Disable Future Gallery Orders
            </button>
          """
      end
    else
      ~H"""
        <h3 class="font-sans">Delete gallery</h3>
        <p class="font-sans">
          If you want to start completely over, or there’s another reason you want to delete the whole gallery, this is
          the place for you.
        </p>
        <button {testid("deleteGalleryPopupButton")} phx-click={"delete_gallery_popup"} class="justify-center w-full py-3 font-sans border border-black rounded-lg mt-7" id="deleteGalleryPopupButton">
          Delete gallery
        </button>
      """
    end
  end

  @impl true
  defdelegate handle_event(event, params, socket), to: TodoplaceWeb.GalleryLive.Shared

  defp fetch_gallery!(id),
    do:
      Galleries.get_gallery!(id)
      |> Galleries.load_watermark_in_gallery()
      |> Repo.preload(:photographer, job: :client)
end
