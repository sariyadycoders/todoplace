defmodule TodoplaceWeb.GalleryLive.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view

  require Ecto.Query

  import TodoplaceWeb.GalleryLive.Shared
  import TodoplaceWeb.Live.Shared, only: [make_popup: 2]

  alias Ecto.Query
  alias Todoplace.{Galleries, Job, Repo, Orders}

  defmodule Pagination do
    @moduledoc false
    defstruct first_index: 1,
              last_index: 4,
              total_count: 0,
              limit: 12,
              after: nil,
              before: nil
  end

  @impl true
  def mount(
        params,
        _session,
        socket
      ) do
    socket
    |> is_mobile(params)
    |> assign_new(:pagination, fn -> %Pagination{} end)
    |> update_gallery_listing()
    |> is_mobile(params)
    |> ok()
  end

  @impl true
  def handle_event(
        "show_dropdown",
        %{"show_index" => show_index},
        socket
      ) do
    show_index = String.to_integer(show_index)

    socket
    |> assign(index: show_index)
    |> noreply()
  end

  @impl true
  def handle_event(
        "page",
        %{"cursor" => cursor, "direction" => direction},
        socket
      ) do
    update_fn =
      case direction do
        "back" -> &%{&1 | after: nil, before: cursor, first_index: &1.first_index - &1.limit}
        "forth" -> &%{&1 | after: cursor, before: nil, first_index: &1.first_index + &1.limit}
      end

    socket
    |> update(:pagination, update_fn)
    |> pagination()
    |> noreply()
  end

  @impl true
  def handle_event(
        "page",
        %{"pagination" => %{"limit" => limit}},
        socket
      ) do
    limit = String.to_integer(limit)

    socket
    |> assign(:pagination, %Pagination{limit: limit, last_index: limit})
    |> pagination()
    |> noreply()
  end

  @impl true
  def handle_event("page", %{}, socket), do: socket |> noreply()

  @impl true
  def handle_event(
        "open_compose",
        %{},
        %{assigns: %{index: index, jobs: jobs}} = socket
      ) do
    job = Enum.at(jobs, index)

    socket
    |> assign(:job, job)
    |> open_compose()
  end

  @impl true
  def handle_event(
        "delete_gallery_popup",
        %{"id" => gallery_id},
        socket
      ) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      close_label: "Cancel",
      confirm_event: "delete_gallery",
      confirm_label: "Yes, delete",
      icon: "warning-orange",
      title: "Delete this gallery?",
      subtitle: "Are you sure you wish to permanently delete this gallery?"
    })
    |> assign(:gallery_id, gallery_id)
    |> noreply()
  end

  @impl true
  def handle_event("disable_gallery_popup", params, socket) do
    opts = [
      event: "disable_gallery",
      title: "Disable Orders?",
      confirm_label: "Yes, disable orders",
      payload: params,
      subtitle:
        "If you disable orders, the gallery will remain intact, but you won’t be able to update it anymore. Your client will still be able to view the gallery."
    ]

    make_popup(socket, opts)
  end

  @impl true
  def handle_event("enable_gallery_popup", params, socket) do
    opts = [
      event: "enable_gallery",
      title: "Enable Orders?",
      confirm_label: "Yes, enable orders",
      payload: params,
      subtitle:
        "If you enable the gallery, your clients will be able to make additional gallery purchases moving forward."
    ]

    make_popup(socket, opts)
  end

  @impl true
  def handle_event("create_gallery", %{}, socket),
    do:
      socket
      |> open_modal(
        TodoplaceWeb.GalleryLive.CreateComponent,
        Map.take(socket.assigns, [:current_user, :currency])
      )
      |> noreply()

  @impl true
  def handle_event("view_gallery", %{"id" => id}, socket),
    do:
      socket
      |> push_redirect(
        to: ~p"/galleries/#{id}?#{%{is_mobile: false}}"
      )
      |> noreply()

  @impl true
  def handle_event("view_job", %{"id" => id}, socket),
    do:
      socket
      |> push_redirect(to: ~p"/jobs/#{id}")
      |> noreply()

  @impl true
  def handle_info({:confirm_event, "send_another"}, socket), do: open_compose(socket)

  @impl true
  def handle_info({:message_composed, message_changeset, recipients}, socket) do
    add_message_and_notify(socket, message_changeset, recipients)
  end

  def handle_info({:success_event, "view-gallery", %{gallery_id: gallery_id}}, socket) do
    socket
    |> push_redirect(
      to: ~p"/galleries/#{gallery_id}?#{%{is_mobile: false}}"
    )
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "disable_gallery", %{"id" => gallery_id}},
        socket
      ) do
    Galleries.get_gallery!(String.to_integer(gallery_id))
    |> Galleries.update_gallery(%{status: :disabled})
    |> process_gallery(socket, :disabled)
  end

  @impl true
  def handle_info(
        {:confirm_event, "enable_gallery", %{"id" => gallery_id}},
        socket
      ) do
    Galleries.get_gallery!(String.to_integer(gallery_id))
    |> Galleries.update_gallery(%{status: :active})
    |> process_gallery(socket, :enabled)
  end

  @impl true
  def handle_info(
        {:confirm_event, "delete_gallery"},
        %{assigns: %{gallery_id: gallery_id}} = socket
      ) do
    {:ok, _} = String.to_integer(gallery_id) |> Galleries.delete_gallery_by_id()

    socket
    |> update_gallery_listing()
    |> close_modal()
    |> put_flash(:success, "Gallery deleted successfully")
    |> noreply()
  end

  @impl true
  def handle_info({:redirect_to_gallery, gallery}, socket) do
    TodoplaceWeb.Live.Shared.handle_info({:redirect_to_gallery, gallery}, socket)
  end

  def image_item(%{gallery: gallery} = assigns) do
    albums =
      case gallery.type do
        :standard ->
          ngettext("%{count} album", "%{count} albums", Enum.count(gallery.albums))

        :proofing ->
          "Proofing"

        _ ->
          "Finals"
      end

    assigns = assign(assigns, albums: albums)

    ~H"""
      <div class="flex flex-wrap w-full md:w-auto">
        <div class="flex flex-col md:flex-row grow">
          <%= if @gallery.cover_photo do %>
            <div>
              <.link navigate={~p"/galleries/#{gallery.id}?#{%{is_mobile: false}}"}>
                <div class="rounded-lg float-left w-[200px] mr-4 md:mr-7 min-h-[130px]" style={"background-image: url('#{cover_photo_url(@gallery)}'); background-repeat: no-repeat; background-size: cover; background-position: center;"}></div>
              </.link>
            </div>
          <% else %>
            <div class="rounded-lg h-full p-4 items-center flex flex-col w-[200px] h-[130px] mr-4 md:mr-7 bg-base-200">
              <div class="flex justify-center h-full items-center">
                <.icon name="photos-2" class="inline-block w-9 h-9 text-base-250"/>
              </div>
              <div class="mt-1 text-base-250 text-center h-full">
                <span>Edit your gallery to upload a cover photo</span>
              </div>
            </div>
          <% end %>
        </div>

        <div class="py-0 md:py-2 mt-4 md:mt-0">
          <div class="font-bold">
            <%= Calendar.strftime(@gallery.inserted_at, "%m/%d/%y") %>
          </div>
          <div class={"font-bold w-full"}>
            <.link navigate={~p"/galleries/#{@gallery.id}?#{%{is_mobile: false}}"}>
              <span class="w-full text-blue-planning-300 underline">
                <%= if String.length(@gallery.name) < 30 do
                  @gallery.name
                else
                  "#{@gallery.name |> String.slice(0..29)} ..."
                end %>
              </span>
            </.link>
          </div>
          <div class="text-base-250 font-normal ">
            <%= @albums %>
          </div>
        </div>
      </div>
    """
  end

  defp open_compose(%{assigns: %{current_user: current_user, job: job}} = socket),
    do:
      socket
      |> TodoplaceWeb.ClientMessageComponent.open(%{
        modal_title: "Send an email",
        show_client_email: true,
        show_subject: true,
        presets: [],
        send_button: "Send",
        client: Job.client(job),
        current_user: current_user
      })
      |> noreply()

  defp get_jobs_list(galleries) do
    galleries
    |> Enum.reduce([], fn gallery, acc ->
      acc ++ [gallery.job]
    end)
  end

  def pagination(%{assigns: assigns} = socket) do
    assigns = Map.put_new(assigns, :pagination, %Pagination{})
    put_assigns(socket, assigns)
  end

  def update_gallery_listing(%{assigns: assigns} = socket) do
    assigns = Map.put(assigns, :pagination, %Pagination{})
    put_assigns(socket, assigns)
  end

  def put_assigns(socket, %{current_user: current_user} = assigns) do
    pagination = Map.get(assigns, :pagination)
    action = Map.get(assigns, :live_action)
    organization_id = Map.get(current_user, :organization).id

    %{entries: galleries, metadata: metadata} =
      Galleries.list_all_galleries_by_organization_query(organization_id)
      |> Query.order_by(desc: :updated_at)
      |> Repo.paginate(
        pagination
        |> Map.take([:before, :after, :limit])
        |> Map.to_list()
        |> Enum.concat(cursor_fields: [updated_at: :desc])
      )

    jobs = get_jobs_list(galleries)

    galleries =
      Enum.map(galleries, fn gallery ->
        orders = Orders.all(gallery.id)
        Map.put(gallery, :orders, orders)
      end)

    socket
    |> assign(:page_title, action |> Phoenix.Naming.humanize())
    |> assign(:galleries, galleries |> Repo.preload([:orders]))
    |> assign(:jobs, jobs)
    |> assign(:index, false)
    |> assign(
      pagination: %{
        pagination
        | total_count: metadata.total_count,
          after: metadata.after,
          before: metadata.before,
          last_index: pagination.first_index + Enum.count(jobs) - 1
      }
    )
  end

  defp dropdown_item(%{icon: _} = assigns) do
    assigns =
      Enum.into(assigns, %{class: "", id: "", disable: false, action: "", value: "", icon: ""})

    ~H"""
    <div title={@title} type="button" phx-click={@action} phx-value-id={@value} class={classes("cursor-pointer text-gray-700 block px-4 py-2 text-sm hover:bg-blue-planning-100", %{"opacity-50 hover:opacity-30 hover:cursor-not-allowed" => @disable})}>
      <.icon name={@icon} class={classes("w-4 h-4 fill-current inline mr-1", %{"text-red-sales-300" => @icon == "trash" || @icon == "closed-eye", "text-blue-planning-300" => @icon != "trash" && @icon != "closed-eye"})} />
      <%= @title %>
    </div>
    """
  end

  def process_gallery(result, socket, type) do
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

  defp process_gallery_message(socket, type, _gallery) do
    case type do
      "deleted" ->
        socket
        |> push_redirect(to: ~p"/galleries")
        |> put_flash(:success, "The gallery has been #{type}")
        |> noreply()

      _any ->
        socket
        |> push_redirect(to: ~p"/galleries")
        |> close_modal()
        |> put_flash(:success, "The gallery has been #{type}")
        |> noreply()
    end
  end
end
