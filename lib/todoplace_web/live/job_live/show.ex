defmodule TodoplaceWeb.JobLive.Show do
  @moduledoc false
  use TodoplaceWeb, :live_view

  alias Todoplace.{
    Job,
    Repo,
    EmailAutomationSchedules,
    Galleries,
    Galleries.Gallery,
    BookingProposal
  }

  alias TodoplaceWeb.JobLive.GalleryTypeComponent

  import TodoplaceWeb.JobLive.Shared,
    only: [
      assign_job: 2,
      card: 1,
      history_card: 1,
      package_details_card: 1,
      client_details_section: 1,
      client_documents_section: 1,
      client_documents_extra_section: 1,
      finance_details_section: 1,
      finances_section: 1,
      inbox_section: 1,
      notes_editor: 1,
      tabs_list: 1,
      view_title: 1,
      simple_card: 1,
      presign_entry: 2,
      shoot_details_section: 1,
      validate_payment_schedule: 1,
      card_title: 1,
      process_cancel_upload: 2,
      renew_uploads: 3,
      complete_job_component: 1
    ]

  import TodoplaceWeb.GalleryLive.Shared, only: [expired_at: 1]

  @upload_options [
    accept: ~w(.pdf .docx .txt),
    auto_upload: true,
    external: &presign_entry/2,
    progress: &__MODULE__.handle_progress/3,
    max_entries: 2,
    max_file_size: String.to_integer(Application.compile_env(:todoplace, :document_max_size))
  ]

  @impl true
  def mount(
        %{"id" => job_id} = params,
        _session,
        %{assigns: %{current_user: _current_user}} = socket
      ) do
    socket
    |> assign_job(job_id)
    |> assign(:main_class, "bg-gray-100")
    |> assign(:tabs, tabs_list(:jobs))
    |> assign(:tab_active, "overview")
    |> assign_tab_data("overview")
    |> assign(:type, %{singular: "job", plural: "jobs"})
    |> assign_new(:anchor, fn -> Map.get(params, "anchor", nil) end)
    |> assign(:request_from, params["request_from"])
    |> assign(:collapsed_sections, [])
    |> assign(:new_gallery, nil)
    |> is_mobile(params)
    |> assign_emails_count(job_id)
    |> subscribe_emails_count(job_id)
    |> then(fn %{assigns: %{job: job}} = socket ->
      payment_schedules = job |> Repo.preload(:payment_schedules) |> Map.get(:payment_schedules)

      socket
      |> assign(payment_schedules: payment_schedules)
      |> assign(:invalid_entries, [])
      |> assign(:invalid_entries_errors, %{})
      |> allow_upload(:documents, @upload_options)
      |> validate_payment_schedule()
    end)
    |> ok()
  end

  @impl true
  def handle_params(%{"tab_active" => tab_active}, _, socket) do
    socket
    |> assign(:tab_active, tab_active)
    |> assign_tab_data(tab_active)
    |> noreply()
  end

  @impl true
  def handle_params(_, _, socket) do
    socket
    |> noreply()
  end

  @impl true
  def handle_event("confirm_job_complete", %{}, socket) do
    socket
    |> complete_job_component()
    |> noreply()
  end

  @impl true
  def handle_event("intro_js" = event, params, socket),
    do: TodoplaceWeb.LiveHelpers.handle_event(event, params, socket)

  @impl true

  def handle_event("open-stripe", _, %{assigns: %{job: job, current_user: current_user}} = socket) do
    client = job |> Repo.preload(:client) |> Map.get(:client)

    socket
    |> redirect(
      external:
        "https://dashboard.stripe.com/#{current_user.organization.stripe_account_id}/customers/#{client.stripe_customer_id}"
    )
    |> noreply()
  end

  def handle_event("view-orders", %{"gallery_id" => gallery_id}, socket),
    do:
      socket
      |> push_redirect(to: ~p"/galleries/#{gallery_id}/transactions")
      |> noreply()

  @impl true
  def handle_event(
        "edit-digital-pricing",
        %{"gallery_id" => gallery_id},
        %{assigns: %{is_mobile: is_mobile}} = socket
      ) do
    socket
    |> redirect(to: ~p"/galleries/#{gallery_id}/pricing")
    |> noreply
  end

  @impl true
  def handle_event("view-gallery", %{"gallery_id" => gallery_id}, socket),
    do:
      socket
      |> push_redirect(to: ~p"/galleries/#{gallery_id}?#{%{is_mobile: false}}")
      |> noreply()

  def handle_event("create-gallery", %{"parent_id" => parent_id}, socket) do
    send(self(), {:gallery_type, {"finals", parent_id}})

    noreply(socket)
  end

  @impl true
  def handle_event("create-gallery", _, %{assigns: %{job: job}} = socket) do
    socket
    |> open_modal(GalleryTypeComponent, %{job: job, from_job?: true})
    |> noreply()
  end

  @impl true
  def handle_event("change-tab", %{"tab" => tab}, socket) do
    socket
    |> patch(tab_active: tab)
  end

  def handle_event(
        "cancel-upload",
        %{"ref" => ref},
        socket
      ) do
    socket
    |> process_cancel_upload(ref)
    |> noreply()
  end

  @impl true
  def handle_event(
        "copy-or-view-client-link",
        %{"action" => "view"},
        %{assigns: %{job: job}} = socket
      ) do
    proposal = BookingProposal.for_job(job.id) |> Repo.one()

    socket
    |> push_event("ViewClientLink", %{"url" => BookingProposal.url(proposal.id)})
    |> noreply()
  end

  @impl true
  defdelegate handle_event(name, params, socket), to: TodoplaceWeb.JobLive.Shared

  @impl true
  def handle_info({:action_event, "confirm_job_complete"}, socket) do
    socket
    |> complete_job_component()
    |> noreply()
  end

  @impl true
  def handle_info({:confirm_event, "complete_job"}, %{assigns: %{job: job}} = socket) do
    case job |> Job.complete_changeset() |> Repo.update() do
      {:ok, job} ->
        socket
        |> assign_job(job.id)
        |> close_modal()
        |> put_flash(:success, "Job completed")
        |> push_redirect(to: ~p"/jobs")
        |> noreply()

      {:error, _} ->
        socket
        |> close_modal()
        |> put_flash(:error, "Failed to complete job. Please try again.")
        |> noreply()
    end
  end

  @impl true
  def handle_info(
        {:gallery_type, opts},
        %{assigns: %{job: job, current_user: %{organization_id: organization_id} = current_user}} =
          socket
      ) do
    {type, parent_id} = split(opts)

    {:ok, gallery} =
      Galleries.create_gallery(current_user, %{
        job_id: job.id,
        from_job?: true,
        type: type,
        parent_id: parent_id,
        client_link_hash: UUID.uuid4(),
        name: Job.name(job) <> " #{Enum.count(job.galleries) + 1}",
        expired_at: expired_at(organization_id),
        albums: Galleries.album_params_for_new(type)
      })

    send(self(), {:redirect_to_gallery, gallery})

    socket
    |> assign(:new_gallery, gallery)
    |> noreply()
  end

  @impl true
  def handle_info({:redirect_to_gallery, gallery}, socket) do
    TodoplaceWeb.Live.Shared.handle_info({:redirect_to_gallery, gallery}, socket)
  end

  @impl true
  def handle_info({:update_emails_count, %{job_id: job_id}}, socket) do
    socket
    |> assign_emails_count(job_id)
    |> noreply()
  end

  @impl true
  defdelegate handle_info(message, socket), to: TodoplaceWeb.JobLive.Shared

  def handle_progress(
        :documents,
        entry,
        %{
          assigns: %{
            job: %{documents: documents} = job,
            uploads: %{documents: %{entries: entries}}
          }
        } = socket
      ) do
    if entry.done? do
      key = Job.document_path(entry.client_name, entry.uuid)

      job =
        Todoplace.Job.document_changeset(job, %{
          documents: [
            %{name: entry.client_name, url: key}
            | Enum.map(documents, &%{name: &1.name, url: &1.url})
          ]
        })
        |> Repo.update!()

      entries
      |> Enum.reject(&(&1.uuid == entry.uuid))
      |> renew_uploads(entry, socket)
      |> assign(:job, job)
      |> noreply()
    else
      socket |> noreply()
    end
  end

  def gallery_attrs(%Gallery{type: type} = gallery, parent_has_orders? \\ false) do
    case Todoplace.Galleries.gallery_current_status(gallery) do
      :none_created when type == :finals ->
        %{
          button_text: "Create finals",
          button_click: "create-gallery",
          button_disabled: !parent_has_orders?,
          text: text(:finals, :none_created, parent_has_orders?),
          status: :none_created
        }

      :none_created ->
        %{
          button_text: "Create Gallery",
          button_click: "create-gallery",
          button_disabled: false,
          text: "You don't have galleries for this job. Create one now!",
          status: :none_created
        }

      :no_photo when type == :finals ->
        %{
          button_text: "Upload Finals",
          button_click: "view-gallery",
          button_disabled: false,
          text: "Selects are ready",
          status: :no_photo
        }

      :no_photo ->
        %{
          button_text: "Upload Photos",
          button_click: "view-gallery",
          button_disabled: false,
          text: "Upload photos",
          status: :no_photo
        }

      :deactivated ->
        %{
          button_text: "View gallery",
          button_click: "view-gallery",
          button_disabled: true,
          text: "Gallery is disabled",
          status: :deactivated
        }

      status ->
        photos_count = Galleries.get_gallery_photos_count(gallery.id)

        %{
          button_text: button_text(type),
          button_click: "view-gallery",
          button_disabled: false,
          text: "#{photos_count} #{ngettext("photo", "photos", photos_count)}",
          status: status
        }
    end
  end

  defp assign_tab_data(%{assigns: %{current_user: _current_user}} = socket, tab) do
    case tab do
      "notes" ->
        socket
        |> assign(:notes_changeset, build_notes_changeset(socket, %{}))

      _ ->
        socket
    end
  end

  defp text(:finals, :none_created, true), do: "Selects are ready"
  defp text(:finals, :none_created, false), do: "Need selects from client first"

  defp button_text(:proofing), do: "View selects"
  defp button_text(:finals), do: "View finals"
  defp button_text(_), do: "View gallery"

  defp actions(assigns) do
    ~H"""
    <div
      class="flex items-center md:ml-auto w-full md:w-auto left-3 sm:left-8"
      data-offset-x="-21"
      phx-update="ignore"
      data-placement="bottom-end"
      phx-hook="Select"
      id={"manage-gallery-#{@gallery.id}"}
    >
      <button
        title="Manage"
        class="btn-tertiary px-3 py-2 flex items-center gap-3 mr-2 text-blue-planning-300 xl:w-auto w-full"
      >
        Actions
        <.icon
          name="down"
          class="w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 open-icon"
        />
        <.icon
          name="up"
          class="hidden w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 close-icon"
        />
      </button>

      <div class="z-10 flex flex-col hidden w-68 bg-white border rounded-lg shadow-lg popover-content">
        <%= for %{title: title, action: action, icon: icon} <- actions() do %>
          <button
            title={title}
            type="button"
            disabled={!@disabled}
            phx-click={action}
            phx-value-gallery_id={@gallery.id}
            class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold disabled:opacity-75 disabled:cursor-not-allowed"
          >
            <.icon
              name={icon}
              class={
                classes("inline-block w-4 h-4 mr-3 fill-current", %{
                  "text-red-sales-300" => icon == "trash",
                  "text-blue-planning-300" => icon != "trash"
                })
              }
            />
            <%= title %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp galleries(%{galleries: [], leads_jobs_redesign: true} = assigns) do
    %{
      button_text: button_text,
      button_click: button_click,
      button_disabled: button_disabled,
      text: text
    } = gallery_attrs(%Gallery{})

    assigns =
      assigns
      |> Map.put(:button_text, button_text)
      |> Map.put(:button_click, button_click)
      |> Map.put(:button_disabled, button_disabled)
      |> Map.put(:text, text)

    ~H"""
    <.simple_card icon="gallery" heading="Galleries">
      <div {testid("card-Gallery")}>
        <p class="text-base-250"><%= @text %></p>
        <button
          class="btn-primary mt-4 intro-gallery"
          phx-click={@button_click}
          disabled={@button_disabled}
        >
          <%= @button_text %>
        </button>
      </div>
    </.simple_card>
    """
  end

  defp galleries(%{galleries: []} = assigns) do
    %{
      button_text: button_text,
      button_click: button_click,
      button_disabled: button_disabled,
      text: text
    } = gallery_attrs(%Gallery{})

    assigns =
      assigns
      |> Map.put(:button_text, button_text)
      |> Map.put(:button_click, button_click)
      |> Map.put(:button_disabled, button_disabled)
      |> Map.put(:text, text)

    ~H"""
    <div {testid("card-Gallery")}>
      <p><%= @text %></p>
      <button
        class="btn-primary mt-4 intro-gallery"
        phx-click={@button_click}
        disabled={@button_disabled}
      >
        <%= @button_text %>
      </button>
    </div>
    """
  end

  defp galleries(%{galleries: _galleries} = assigns) do
    build_type = fn
      :finals -> :unlinked_finals
      type -> type
    end

    assigns = assigns |> Map.put(:build_type, build_type)

    ~H"""
    <%= for %{name: name, type: type, child: child, orders: orders} = gallery <- @galleries do %>
      <%= case type do %>
        <% :proofing -> %>
          <div
            {testid("card-proofing")}
            class="flex overflow-hidden border border-base-200 rounded-lg"
          >
            <div class="flex flex-col w-full p-4">
              <.card_title title={name} gallery_type={type} color="black" gallery_card?={true} />
              <div class="flex justify-between w-full">
                <.card_content
                  gallery={gallery}
                  icon_name="proofing"
                  title="Client Proofing"
                  padding="pr-3"
                  {assigns}
                />
                <div class="h-full w-px bg-base-200" />
                <.card_content
                  gallery={child || %Gallery{type: :finals, orders: []}}
                  parent_id={gallery.id}
                  parent_has_orders?={Enum.any?(orders, & &1.placed_at)}
                  icon_name="finals"
                  title="Client Finals"
                  padding="pl-3"
                  {assigns}
                />
              </div>
            </div>
          </div>
        <% _ -> %>
          <.card title={name} gallery_card?={true} color="black" gallery_type={@build_type.(type)}>
            <.inner_section
              {assigns}
              gallery={gallery}
              p_class="text-lg"
              btn_section_class="mt-[3.7rem]"
              link_class="font-semibold text-base"
            />
          </.card>
      <% end %>
    <% end %>
    """
  end

  defp card_content(assigns) do
    ~H"""
    <div class={"flex flex-col w-2/4 #{@padding}"}>
      <div class="flex">
        <div class="border p-1.5 rounded-full bg-base-200">
          <.icon name={@icon_name} class="w-4 h-4 stroke-2 fill-current text-blue-planning-300" />
        </div>
        <span class="mt-0.5 ml-3 text-base font-bold"><%= @title %></span>
      </div>
      <.inner_section {assigns} btn_class="px-2" socket={@socket} />
    </div>
    """
  end

  defp inner_section(%{gallery: %{orders: orders}} = assigns) do
    assigns =
      Enum.into(
        assigns,
        %{
          p_class: "text-base h-12",
          btn_section_class: "mt-2",
          btn_class: "px-3",
          count: Enum.count(orders, & &1.placed_at),
          parent_has_orders?: true,
          parent_id: nil
        }
      )

    ~H"""
    <%= case gallery_attrs(@gallery, @parent_has_orders?) do %>
      <% %{button_text: button_text, button_click: button_click, button_disabled: button_disabled, text: text, status: status} -> %>
        <p class={"text-base-250 font-normal #{@p_class}"}>
          <%= text %>
          <%= unless status in [:no_photo, :none_created] do %>
            - <%= if @count == 0,
              do: "No orders",
              else: "#{@count} " <> ngettext("order", "orders", @count) %>
          <% end %>
        </p>
        <div {testid("card-buttons")} class={"flex self-end items-center gap-4 #{@btn_section_class}"}>
          <button
            class={"btn-primary intro-gallery font-normal rounded-lg py-2 #{@btn_class}"}
            phx-click={button_click}
            phx-value-gallery_id={@gallery.id}
            phx-value-parent_id={@parent_id}
            disabled={button_disabled}
          >
            <%= button_text %>
          </button>
          <.actions gallery={@gallery} disabled={@parent_has_orders?} />
        </div>
    <% end %>
    """
  end

  defp actions do
    [
      %{title: "View orders", action: "view-orders", icon: "shopping-cart"},
      %{title: "Edit digital pricing & credits", action: "edit-digital-pricing", icon: "pencil"}
    ]
  end

  defp split({type, parent_id}), do: {type, parent_id}
  defp split(type), do: {type, nil}

  defp assign_emails_count(socket, job_id) do
    socket
    |> assign(:emails_count, EmailAutomationSchedules.get_active_email_schedule_count(job_id))
  end

  defp subscribe_emails_count(socket, job_id) do
    Phoenix.PubSub.subscribe(
      Todoplace.PubSub,
      "emails_count:#{job_id}"
    )

    socket
  end

  defp patch(%{assigns: %{job: job}} = socket, opts) do
    socket
    |> push_patch(to: ~p"/jobs/#{job.id}?#{opts}")
    |> noreply()
  end

  defp build_notes_changeset(%{assigns: %{job: job}}, params) do
    Job.notes_changeset(job, params)
  end
end
