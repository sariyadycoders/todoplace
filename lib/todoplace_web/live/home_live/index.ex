defmodule TodoplaceWeb.HomeLive.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view
  use TodoplaceWeb.Live.EventWrapper
  require Logger

  alias Todoplace.{
    Job,
    Jobs,
    Payments,
    Repo,
    Accounts,
    Accounts.User.Promotions,
    Shoots,
    Accounts.User,
    ClientMessage,
    Subscriptions,
    Orders,
    OrganizationCard,
    Utils,
    Onboardings,
    Clients,
    Subscriptions,
    Marketing,
    Galleries,
    Package,
    Packages,
    BookingEvents
  }

  alias TodoplaceWeb.Router.Helpers, as: Routes

  alias TodoplaceWeb.{
    Live.ClientLive.ClientFormComponent,
    JobLive.ImportWizard,
    QuestionnaireFormComponent
  }

  alias TodoplaceWeb.Live.Calendar.BookingEvents.Index
  alias TodoplaceWeb.Calendar.BookingEvents.Shared, as: BEShared

  import TodoplaceWeb.JobLive.Shared, only: [status_badge: 1, open_email_compose: 1]
  import TodoplaceWeb.ClientBookingEventLive.Shared, only: [blurred_thumbnail: 1]
  import TodoplaceWeb.Gettext, only: [ngettext: 3]

  import TodoplaceWeb.GalleryLive.Shared,
    only: [clip_board: 2, cover_photo_url: 1]

  import Ecto.Query
  import Ecto.Changeset, only: [get_change: 2]
  import Phoenix.LiveView
  # import TodoplaceWeb.LiveHelpers
  import Phoenix.Component

  @card_concise_name_list [
    "send-confirmation-email",
    "open-user-settings",
    "getting-started-todoplace",
    "set-up-stripe",
    "open-billing-portal",
    "missing-payment-method",
    "black-friday"
  ]

  @impl true
  def mount(params, _session, %{assigns: %{current_user: current_user}} = socket) do
    %{value: black_friday_code} =
      Todoplace.AdminGlobalSettings.get_settings_by_slug("black_friday_code")

    socket
    |> assign(:main_class, "bg-gray-100")
    |> assign_stripe_status()
    |> assign(:page_title, "Work Hub")
    |> assign(:stripe_subscription_status, nil)
    |> assign_counts()
    |> assign(:promotion_code_open, false)
    |> assign(
      :current_sale,
      Promotions.get_user_promotion_by_slug(current_user, black_friday_code)
    )
    |> assign_attention_items()
    |> assign(:tabs, tabs_list(socket))
    |> assign(:tab_active, "todo")
    |> assign(:index, false)
    |> subscribe_inbound_messages()
    |> assign_inbox_threads()
    |> maybe_show_success_subscription(params)
    |> assign(
      :promotion_code,
      nil
    )
    |> assign_promotion_code_changeset()
    |> ok()
  end

  @impl true
  def handle_params(
        %{"pre_purchase" => "true", "checkout_session_id" => _},
        _uri,
        %{assigns: %{promotion_code: promotion_code, current_user: current_user}} = socket
      ) do
    Promotions.insert_or_update_promotion(current_user, %{
      slug: promotion_code,
      state: :purchased,
      name: "Holiday"
    })

    Onboardings.user_update_promotion_code_changeset(current_user, %{
      onboarding: %{
        promotion_code: promotion_code
      }
    })
    |> Repo.update!()

    socket
    |> put_flash(:success, "Year extended!")
    |> noreply()
  end

    @impl true
  def handle_params(_params, _uri, socket), do: socket |> noreply()

    @impl true
      def handle_event("system-settings", _, %{assigns: %{current_user_data: user_data}} = socket) do
         socket
        |> open_modal(TodoplaceWeb.Live.Admin.SystemSettings, %{
          user_data: user_data,
        })
        |> noreply()
      end

      @impl true
      def handle_event("add-organization", _, %{assigns: %{current_user_data: user_data}} = socket) do
         socket
        |> open_modal(TodoplaceWeb.OrganizationLive.AddOrganizationComponent, %{
          user_data: user_data,
        })
        |> noreply()
      end

      @impl true
      def handle_event("create-organization", _, %{assigns: %{current_user_data: user_data}} = socket) do
         socket
        |> open_modal(TodoplaceWeb.OrganizationLive.CreateOrganizationComponent, %{
          user_data: user_data,
          current_path: "/home",
          organization_page: false
        })
        |> noreply()
      end

  @impl true
  def handle_event(
        "redirect-welcome-route",
        %{},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    socket
    |> assign(:current_user, Onboardings.increase_welcome_count!(current_user))
    |> redirect(to: ~p"/users/welcome")
    |> noreply()
  end

  @impl true
  def handle_event(
        "handle-promotion-code-toggle",
        _,
        %{assigns: %{promotion_code_open: promotion_code_open}} = socket
      ) do
    socket
    |> assign(:promotion_code_open, !promotion_code_open)
    |> noreply()
  end

  @impl true
  def handle_event("create-lead", %{}, %{assigns: %{current_user: current_user}} = socket),
    do:
      socket
      |> open_modal(
        TodoplaceWeb.JobLive.NewComponent,
        %{current_user: current_user}
      )
      |> noreply()

  @impl true
  def handle_event("create-gallery", %{}, %{assigns: assigns} = socket) do
    socket
    |> open_modal(
      TodoplaceWeb.GalleryLive.CreateComponent,
      Map.take(assigns, [:current_user, :currency])
    )
    |> noreply()
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
  def handle_event("open-user-settings", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/users/settings")
      |> noreply()

  @impl true
  def handle_event("questionnaires", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/questionnaires")
      |> noreply()

  @impl true
  def handle_event("clients", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/clients")
      |> noreply()

  @impl true
  def handle_event("global-gallery-settings", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/galleries/settings")
      |> noreply()

  @impl true
  def handle_event(
        "send-confirmation-email",
        %{},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case Accounts.deliver_user_confirmation_instructions(
           current_user,
           &url(~p"/users/confirm/#{&1}")
         ) do
      {:ok, _} ->
        socket
        |> TodoplaceWeb.ConfirmationComponent.open(%{
          title: "Email sent",
          subtitle: "The confirmation email has been sent. Please check your inbox."
        })
        |> noreply()

      {:error, _} ->
        socket |> put_flash(:error, "Failed to send email.") |> noreply()
    end
  end

  @impl true
  def handle_event("open-billing-portal", %{}, socket) do
    {:ok, url} =
      Subscriptions.billing_portal_link(
        socket.assigns.current_user,
        url(~p"/home")
      )

    socket |> redirect(external: url) |> noreply()
  end

  @impl true
  def handle_event(
        "validate-promo-code",
        %{"user" => user_params},
        socket
      ) do
    socket
    |> assign_promotion_code_changeset(user_params)
    |> noreply()
  end

  @impl true
  def handle_event(
        "save-promo-code",
        %{"user" => user_params},
        %{assigns: %{promotion_code_open: promotion_code_open}} = socket
      ) do
    socket
    |> assign_promotion_code_changeset(user_params)
    |> assign(:promotion_code_open, !promotion_code_open)
    |> noreply()
  end


  @impl true
  def handle_event(
        "subscription-checkout",
        %{"interval" => interval},
        %{
          assigns: %{
            promotion_code_changeset: promotion_code_changeset,
            current_user: %{
              onboarding: %{
                promotion_code: promotion_code
              }
            }
          }
        } = socket
      ) do
    onboarding_changeset =
      promotion_code_changeset
      |> get_change(:onboarding)

    promotion_code_id =
      if !is_nil(promotion_code) and is_nil(onboarding_changeset) do
        Subscriptions.maybe_return_promotion_code_id?(promotion_code)
      else
        case onboarding_changeset do
          nil ->
            nil

          _ ->
            onboarding_changeset
            |> get_change(:promotion_code)
            |> Subscriptions.maybe_return_promotion_code_id?()
        end
      end

    build_subscription_link(socket, interval, promotion_code_id)
  end

  @impl true
  def handle_event(
        "subscription-prepurchase",
        _,
        socket
      ) do
    build_invoice_link(socket)
  end

  @impl true
  def handle_event(
        "subscription-prepurchase-dismiss",
        _,
        %{assigns: %{current_user: current_user, promotion_code: promotion_code}} = socket
      ) do
    case Promotions.insert_or_update_promotion(current_user, %{
           slug: promotion_code,
           name: "Holiday",
           state: :dismissed
         }) do
      {:ok, promotion_code} ->
        socket
        |> assign(
          :current_sale,
          promotion_code
        )
        |> put_flash(:success, "Deal hidden successfully")

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to dismiss promotion")
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "card_status",
        %{"org_card_id" => org_card_id, "status" => status},
        socket
      ) do
    org_card_id = String.to_integer(org_card_id)

    case status do
      "viewed" -> OrganizationCard.viewed!(org_card_id)
      "inactive" -> OrganizationCard.inactive!(org_card_id)
      _ -> nil
    end

    send(self(), :card_status)

    socket |> noreply()
  end

  @impl true
  def handle_event("add-client", _, socket),
    do:
      socket
      |> ClientFormComponent.open()
      |> noreply()

  @impl true
  def handle_event("view-clients", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/clients")
      |> noreply()

  @impl true
  def handle_event("view-leads", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/leads")
      |> noreply()

  @impl true
  def handle_event("view-jobs", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/jobs")
      |> noreply()

  @impl true
  def handle_event("view-galleries", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/galleries")
      |> noreply()

  @impl true
  def handle_event("view-booking-events", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/booking-events")
      |> noreply()

  @impl true
  def handle_event("view-packages", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/package_templates")
      |> noreply()

  @impl true
  def handle_event("add-package", %{}, socket),
    do:
      socket
      |> push_redirect(to: ~p"/package_templates/new")
      |> noreply()

  @impl true
  def handle_event(
        "create-questionnaire",
        %{},
        %{assigns: %{current_user: %{organization_id: organization_id}} = assigns} = socket
      ) do
    assigns =
      Map.merge(assigns, %{
        questionnaire: %Todoplace.Questionnaire{organization_id: organization_id}
      })

    socket
    |> QuestionnaireFormComponent.open(
      Map.merge(Map.take(assigns, [:questionnaire, :current_user]), %{state: :create})
    )
    |> noreply()
  end

  @impl true
  def handle_event("import-job", %{}, socket),
    do:
      socket
      |> open_modal(ImportWizard, Map.take(socket.assigns, [:current_user]))
      |> noreply()

  @impl true
  def handle_event("view-help", _, socket),
    do:
      socket
      |> redirect(external: base_url(:support))
      |> noreply()

  @impl true
  def handle_event("view-calculator", _, socket),
    do:
      socket
      |> push_redirect(to: ~p"/pricing/calculator")
      |> noreply()

  @impl true
  def handle_event(
        "change-tab",
        %{"tab" => tab},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    # reassign user for collapsing sidebar jank
    # since we are looking at the layout with a class
    current_user =
      current_user.id
      |> Accounts.get_user!()
      |> Repo.preload(organization: [:organization_job_types])

    socket
    |> assign(:current_user, current_user)
    |> assign(:tab_active, tab)
    |> assign_tab_data(tab)
    |> noreply()
  end

  @impl true
  def handle_event("open-thread", %{"id" => id, "type" => type}, socket) do
    path = "#{type}-#{id}"

    socket
    |> push_redirect(to: ~p"/inbox/#{path}")
    |> noreply()
  end

  @impl true
  def handle_event("redirect", %{"to" => to, "tab" => "calculator"}, socket) do
    socket
    |> push_event("intercom", %{event: "Pricing calculator"})
    |> push_redirect(to: to)
    |> noreply()
  end

  @impl true
  def handle_event("redirect", %{"to" => to}, socket) do
    socket
    |> push_redirect(to: to)
    |> noreply()
  end

  @impl true
  def handle_event(
        "enable-event",
        %{"event-id" => id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case BookingEvents.enable_booking_event(id, current_user.organization_id) do
      {:ok, _event} ->
        socket
        |> assign_tab_data("booking-events")
        |> put_flash(:success, "Event enabled successfully")
        |> noreply()

      {:error, _} ->
        socket
        |> put_flash(:success, "Error enabling event")
        |> noreply()
    end
  end

  @impl true
  def handle_event(
        "unarchive-event",
        %{"event-id" => id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case BookingEvents.enable_booking_event(id, current_user.organization_id) do
      {:ok, _event} ->
        socket
        |> assign_tab_data("booking-events")
        |> put_flash(:success, "Event unarchive successfully")
        |> noreply()

      {:error, _} ->
        socket
        |> put_flash(:success, "Error unarchiving event")
        |> noreply()
    end
  end

  @impl true
  def handle_event(
        "delete_gallery_popup",
        %{"gallery-id" => gallery_id},
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
  def handle_event(
        "open_compose",
        %{"index" => index},
        %{assigns: %{galleries: galleries}} = socket
      ) do
    gallery = Enum.at(galleries, to_integer(index))

    socket
    |> assign(:job, gallery.job)
    |> open_email_compose()
  end

  @impl true
  defdelegate handle_event(event, params, socket),
    to: TodoplaceWeb.Calendar.BookingEvents.Shared

  @impl true
  def handle_info(
        {:load_template_preview, component, body_html},
        %{assigns: %{current_user: current_user, modal_pid: modal_pid}} = socket
      ) do
    template_preview = Marketing.template_preview(current_user, body_html)

    send_update(
      modal_pid,
      component,
      id: component,
      template_preview: template_preview
    )

    socket
    |> noreply()
  end

  @impl true
  def handle_info({:update, %{questionnaire: _questionnaire}}, socket) do
    socket
    |> put_flash(:success, "Questionnaire saved")
    |> push_redirect(to: ~p"/questionnaires")
    |> noreply()
  end

  @impl true
  def handle_info(
        {:close_event, %{event_name: "toggle_welcome_event"}},
        socket
      ) do
    socket
    |> welcome_modal_state()
    |> noreply()
  end

  @impl true
  def handle_info({:redirect_to_gallery, gallery}, socket) do
    TodoplaceWeb.Live.Shared.handle_info({:redirect_to_gallery, gallery}, socket)
  end

  @impl true
  def handle_info({:stripe_status, status}, socket) do
    socket |> assign(stripe_status: status) |> assign_attention_items() |> noreply()
  end

  @impl true
  def handle_info({:inbound_messages, _message}, %{assigns: %{inbox_count: count}} = socket) do
    socket
    |> assign(:inbox_count, count + 1)
    |> noreply()
  end

  @impl true
  def handle_info(:card_status, socket) do
    socket
    |> assign_attention_items()
    |> noreply()
  end

  @impl true
  def handle_info({:stripe_session_id, stripe_session_id}, socket) do
    case Subscriptions.handle_subscription_by_session_id(stripe_session_id) do
      :ok ->
        socket
        |> assign(:stripe_subscription_status, :success)
        |> TodoplaceWeb.ConfirmationComponent.open(%{
          title: "You have subscribed to Todoplace",
          subtitle:
            "We’re excited to have join Todoplace. You can always manage your subscription in account settings. If you have any trouble, contact support.",
          close_label: "Close",
          close_class: "btn-primary"
        })
        # clear the session_id param
        |> push_patch(to: ~p"/home", replace: true)
        |> noreply()

      _ ->
        socket
        |> put_flash(:error, "Couldn't fetch your Stripe session. Please try again")
        |> noreply()
    end
  end

  @impl true
  def handle_info(
        {:confirm_event, "disable_event_" <> id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case BookingEvents.disable_booking_event(id, current_user.organization_id) do
      {:ok, _event} ->
        socket
        |> put_flash(:success, "Event disabled successfully")

      {:error, _} ->
        socket
        |> put_flash(:success, "Error disabling event")
    end
    |> assign_tab_data("booking-events")
    |> close_modal()
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "archive_event_" <> id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case BookingEvents.archive_booking_event(id, current_user.organization_id) do
      {:ok, _event} ->
        socket
        |> put_flash(:success, "Event archived successfully")

      {:error, _} ->
        socket
        |> put_flash(:success, "Error archiving event")
    end
    |> assign_tab_data("booking-events")
    |> close_modal()
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "delete_gallery"},
        %{assigns: %{gallery_id: gallery_id}} = socket
      ) do
    {:ok, _} = gallery_id |> Galleries.delete_gallery_by_id()

    socket
    |> assign_tab_data("galleries")
    |> close_modal()
    |> put_flash(:success, "Gallery deleted successfully")
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "create-single-event"} = message,
        socket
      ),
      do: Index.handle_info(message, socket)

  defdelegate handle_info(message, socket), to: TodoplaceWeb.JobLive.Shared

  def tabs_nav(assigns) do
    ~H"""
    <ul class="flex overflow-auto gap-6 mb-6 py-6 md:py-0">
      <%= for {true, %{name: name, action: action, concise_name: concise_name, redirect_route: redirect_route}} <- @tabs do %>
        <li class={classes("text-blue-planning-300 font-bold text-lg border-b-4 transition-all shrink-0", %{"opacity-100 border-b-blue-planning-300" => @tab_active === concise_name, "opacity-40 border-b-transparent hover:opacity-100" => @tab_active !== concise_name})}>
          <button type="button" phx-click={action} phx-value-tab={concise_name} phx-value-to={redirect_route}><%= name %></button>
        </li>
      <% end %>
    </ul>
    """
  end

  def tabs_content(%{assigns: assigns}) do
    ~H"""
    <div>
      <%= case @tab_active do %>
        <% "clients" -> %>
          <.recents_card add_event="add-client" view_event="view-clients" hidden={Enum.empty?(@clients)} button_title="Create a client" title="Recent Clients" class="h-auto" color="blue-planning-300">
          <hr class="mb-4 mt-4" />
            <%= case @clients do %>
              <% [] -> %>
              <div class="flex flex-col mt-4 lg:flex-none">
                <.empty_state_base tour_embed="https://demo.arcade.software/y2cGEpUW0B2FoO2BAa1b?embed" cta_class="mt-0" body="Let's start by adding your clients - whether they are new or if existing, feel free to contact Todoplace for help with bulk uploading." third_party_padding="calc(59.916666666666664% + 41px)" show_dismiss={false}>
                  <button type="button" phx-click="add-client" class="link md:w-auto text-center text-xl flex-shrink-0 whitespace-nowrap">Add client</button>
                </.empty_state_base>
                </div>
              <% clients -> %>
              <div class="grid lg:grid-cols-3 md:grid-cols-2 grid-cols-1 gap-5">
                <%= for client <- clients do %>
                  <.link navigate={~p"/clients/#{client.id}"}>
                    <p class="text-blue-planning-300 text-18px font-bold underline hover:cursor-pointer capitalize">
                      <%= if client.name do
                        if String.length(client.name) <= 40 do
                          client.name
                        else
                          "#{client.name |> String.slice(0..40)} ..."
                        end
                      else
                        "-"
                      end %>
                    </p>
                    <p class="text-gray-400 font-normal text-sm">
                      <%= client.email %>
                    </p>
                  </.link>
                <% end %>
              </div>
            <% end %>
          </.recents_card>

        <% "leads" -> %>
        <.recents_card add_event="create-lead" view_event="view-leads" hidden={Enum.empty?(@leads)} button_title="Create a lead" title="Recent Leads" class="h-auto" color="blue-planning-300">
          <hr class="mb-4 mt-4" />
          <%= case @leads do %>
            <% [] -> %>
              <div class="flex md:flex-row flex-col items-center p-4 gap-6">
                <iframe src="https://www.youtube.com/embed/V90oycrU45g" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen class="aspect-video"></iframe>
                <p class="md:max-w-md text-base-250 text-normal mb-8">Generating leads is the pipeline to booked clients. <span class="font-normal text-normal text-blue-planning-300"><a class="underline" target="_blank" rel="noopener noreferrer" href={"#{base_url(:support)}article/40-create-a-lead"}>Learn more</a></span> and create some now.</p>
              </div>
            <% leads -> %>
            <div class="grid lg:grid-cols-3 md:grid-cols-2 grid-cols-1 gap-5">
              <%= for lead <- leads do %>
                <.link navigate={~p"/leads/#{lead.id}"}>
                  <div class="flex flex-row">
                    <p class="text-blue-planning-300 text-18px font-bold underline hover:cursor-pointer capitalize">
                      <%= if String.length(Job.name(lead)) <= 40 do
                          Job.name(lead) || "-"
                        else
                          "#{Job.name(lead) |> String.slice(0..40)} ..."
                        end %>
                    </p>
                    <.status_badge class="ml-4 w-fit" job={lead}/>
                  </div>
                  <p class="text-gray-400 font-normal text-sm">
                    Created <%= lead.inserted_at |> format_date_via_type("MM/DD/YY") |> String.trim("0") %>
                  </p>
                </.link>
              <% end %>
            </div>
          <% end %>
        </.recents_card>

        <% "jobs" -> %>
        <.recents_card add_event="import-job" view_event="view-jobs" hidden={Enum.empty?(@jobs)} button_title="Import a job" title="Upcoming Jobs" class="h-auto">
          <hr class="mt-4 mb-4" />
          <%= case @jobs do %>
            <% [] -> %>
              <div class="flex md:flex-row flex-col items-center p-4 gap-6">
                <iframe src="https://www.youtube.com/embed/XWZH_65evuM" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen class="aspect-video"></iframe>
                <p class="md:max-w-md text-base-250 text-normal mb-8">Booking jobs will get you on your way to making a profit. If you are migrating existing jobs from another platform, use our import a job button above.</p>
              </div>
            <% jobs -> %>
            <div class="grid lg:grid-cols-3 md:grid-cols-2 grid-cols-1 gap-5">
              <%= for job <- jobs do %>
                <.link navigate={~p"/jobs/#{job.id}"}>
                  <p class="text-blue-planning-300 text-18px font-bold underline hover:cursor-pointer capitalize">
                    <%= if String.length(Job.name(job)) <= 40 do
                        Job.name(job) || "-"
                      else
                        "#{Job.name(job) |> String.slice(0..40)} ..."
                      end %>
                  </p>
                  <%= if Shoots.get_next_shoot(job) do %>
                    <p class="text-gray-400 font-normal text-sm">
                      Next Shoot <%= job |> Shoots.get_next_shoot() |> Map.get(:starts_at) |> format_date_via_type("MM/DD/YY") |> String.trim("0") %>
                    </p>
                  <% end %>
                </.link>
              <% end %>
            </div>
          <% end %>
        </.recents_card>

        <% "galleries" -> %>
          <.recents_card add_event="create-gallery" view_event="view-galleries" hidden={Enum.empty?(@galleries)} button_title="Create a gallery" title="Recent Galleries" class="h-auto" color="blue-planning-300">
            <hr class="mt-4 mb-4" />
            <%= case @galleries do %>
              <% [] -> %>
                <div class="flex md:flex-row flex-col items-center p-4 gap-6">
                  <iframe src="https://www.youtube.com/embed/uEY3eS9cDIk" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen class="aspect-video"></iframe>
                  <p class="md:max-w-md text-base-250 text-normal mb-8">With unlimited gallery storage, don't think twice about migrating existing galleries from other platforms and creating new ones.</p>
                </div>
              <% galleries -> %>
              <div class="grid lg:grid-cols-3 md:grid-cols-2 grid-cols-1 md:gap-4 gap-6">
                <%= for {gallery, gallery_index} <- galleries |> Enum.with_index() do %>
                  <.recent_data socket={@socket} data={gallery} index={@index} data_index={gallery_index} />
                <% end %>
              </div>
            <% end %>
          </.recents_card>

        <% "booking-events" -> %>
          <.recents_card add_event="new-event" view_event="view-booking-events" hidden={Enum.empty?(@booking_events)} button_title="Create a booking event" title="Recent Booking Events" class="h-auto" color="blue-planning-300">
            <hr class="mt-4 mb-4" />
            <%= case @booking_events |> Enum.take(6) do %>
              <% [] -> %>
                  <div class="flex md:flex-row flex-col items-center p-4 md:gap-4 gap-6">
                    <iframe src="https://www.youtube.com/embed/aVnPMupMK8Q" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen class="aspect-video"></iframe>
                    <p class="md:max-w-md text-base-250 text-normal mb-8">Booking events are an easy way to get jobs booked, paid and prepped efficiently - for both you and your clients.</p>
                  </div>
              <% booking_events -> %>
              <div class="grid lg:grid-cols-3 md:grid-cols-2 grid-cols-1 gap-5">
                <%= for {booking_event, booking_index} <- booking_events |> Enum.with_index() do %>
                  <.recent_data socket={@socket} data={booking_event} index={@index} data_index={booking_index} />
                <% end %>
              </div>
            <% end %>
          </.recents_card>

        <% "packages" -> %>
          <.recents_card add_event="add-package" view_event="view-packages" hidden={Enum.empty?(@packages)} button_title="Create a package" title="Recent Packages" class="h-auto" color="blue-planning-300">
            <hr class="mt-4 mb-4" />
            <div class="grid lg:grid-cols-3 md:grid-cols-2 grid-cols-1 gap-5">
              <%= for package <- @packages do %>
                <.link navigate={~p"/package_templates/#{package.id}/edit"}>
                  <p class="text-blue-planning-300 text-18px font-bold underline hover:cursor-pointer capitalize">
                    <%= if String.length(package.name) <= 40 do
                        package.name || "-"
                      else
                        "#{package.name |> String.slice(0..40)} ..."
                      end %>
                  </p>
                  <div class="flex flex-col sm:grid sm:grid-cols-2 justify-between text-gray-400 font-normal text-sm break-all gap-1 sm:gap-2">
                    <span>Package price: <%= package |> Package.price() %></span>
                    <span>Digital price: <%= if Money.zero?(package.download_each_price) do %>--<% else %><%= package.download_each_price %> <% end %></span>
                  </div>
                </.link>
              <% end %>
            </div>
          </.recents_card>

        <% "finish-setup" -> %>
          <div class="grid grid-rows-2 gap-5">
            <div class="grid md:grid-cols-2 grid-cols-1 gap-5">
              <%= if @stripe_status != :charges_enabled do %>
                <div {testid("card-finish-setup")} class={"flex border border-base-200 rounded-lg h-auto"}>
                  <div class={"w-3 flex-shrink-0 border-r rounded-l-lg bg-blue-planning-300"} />
                  <div class="flex md:flex-row flex-col mt-4 p-4 gap-6">
                    <iframe src="https://www.youtube.com/embed/8OQSazeLgv8" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen class="aspect-video mb-24"></iframe>
                    <div class="flex flex-col">
                      <h1 class="text-xl font-bold mb-4">Seamless payment thru Stripe</h1>
                      <p class="text-base-250 text-normal mb-8">Stripe is the platform we use to enable swift and automatic client payments processing for you and your business.</p>
                      <.card_buttons {assigns} class="btn-primary" current_user={@current_user} socket={@socket} concise_name={@org_stripe_card.card.concise_name} org_card_id={@org_stripe_card.id} buttons={@org_stripe_card.card.buttons} />
                    </div>
                  </div>
                </div>
              <% end %>

              <div {testid("card-get-started")} class={"flex border border-base-200 rounded-lg h-auto"}>
                <div class={"w-3 flex-shrink-0 border-r rounded-l-lg bg-blue-planning-300"} />
                <div class="flex md:flex-row flex-col mt-4 p-4 gap-6">
                  <iframe src="https://www.youtube.com/embed/8OQSazeLgv8" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen class="aspect-video mb-24"></iframe>
                  <div class="flex flex-col">
                    <h1 class="text-xl font-bold mb-4">Get your packages setup</h1>
                    <p class="text-base-250 text-normal mb-8">Packages are to your business and success! Start with our Smart Profit Calculator™ to calculate pricing and be sure to get your packages set up now.</p>
                    <button type="button" phx-click="view-packages" class="w-full md:w-auto btn-primary flex-shrink-0 text-center">Get Started</button>
                  </div>
                </div>
              </div>
            </div>

            <div {testid("card-finish-setup")} class={"flex border border-base-200 rounded-lg h-auto"}>
              <div class={"w-3 flex-shrink-0 border-r rounded-l-lg bg-blue-planning-300"} />
                <div class="flex flex-col p-4">
                  <div class="flex row">
                    <h1 class="text-xl font-bold mb-4">Todoplace Account Set-up</h1>
                    <.icon name="confetti-welcome" class="inline-block w-7 h-7 text-blue-planning-300" />
                  </div>
                  <p class="text-base-250 text-normal">The classic “Chicken or the Egg” problem. We know it is overwhelming getting started with any software. Here’s what we suggest to do to get familiar and setup:</p>
                </div>
            </div>
          </div>

        <% _ -> %>
          <%= case @attention_items do %>
            <% [] -> %>
              <h6 class="flex items-center font-bold text-blue-planning-300"><.icon name="confetti-welcome" class="inline-block w-8 h-8 text-blue-planning-300" /> You're all caught up!</h6>
            <% items -> %>
              <ul class={classes("flex overflow-auto intro-next-up", %{"xl:overflow-none" => !@should_attention_items_overflow })}>
                <%= for {true, %{card: %{title: title, body: body, icon: icon, buttons: buttons, concise_name: concise_name, color: color, class: class}} = org_card} <- items do %>
                  <li {testid("attention-item")} class={classes("attention-item flex-shrink-0 flex flex-col justify-between relative max-w-sm w-3/4 p-5 cursor-pointer mr-4 border rounded-lg #{class} bg-white border-gray-250", %{"xl:flex-1" => !@should_attention_items_overflow})}>
                    <%= if org_card.status == :viewed and concise_name != "black-friday" do %>
                      <div class="flex justify-between absolute w-full">
                        <span></span>
                        <span class="sm:pr-[30px] pr-[25px]" phx-click="card_status" phx-value-org_card_id={org_card.id} phx-value-status="inactive">
                          <.icon name="close-x" class="mt-[-7px] w-3 h-3 stroke-current stroke-2 base-250" />
                        </span>
                      </div>
                    <% end %>

                    <div>
                      <div class="flex">
                        <.icon name={icon} width="23" height="20" class={"block mr-2 mt-1 rounded-sm fill-current text-#{color}"} />
                        <h1 class="text-lg font-bold"><%= title %></h1>
                      </div>

                      <p class="my-2 text-sm"><%= body %></p>
                    </div>

                    <.card_buttons {assigns} current_user={@current_user} socket={@socket} concise_name={concise_name} org_card_id={org_card.id} buttons={buttons} />
                  </li>
                <% end %>
              </ul>
            <% end %>
      <% end %>
    </div>
    """
  end

  def action_item(assigns) do
    assigns =
      Enum.into(assigns, %{
        button_text: nil,
        button_action: nil,
        button_icon: nil
      })

    ~H"""
    <button title={@button_text} type="button" phx-click={@button_action} class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
      <.icon name={@button_icon} class="inline-block w-4 h-4 mr-3 text-blue-planning-300" />
      <%= @button_text %>
    </button>
    """
  end

  def dashboard_main_card(assigns) do
    assigns =
      Enum.into(assigns, %{
        title: nil,
        inner_block: nil,
        inner_block_classes: nil,
        button_text: nil,
        button_action: nil,
        link_text: nil,
        link_action: nil,
        link_value: nil,
        notification_count: nil,
        redirect_route: nil
      })

    ~H"""
    <div class="rounded-lg border p-4 grow flex flex-col items-start">
      <div class="flex justify-between items-center mb-2 w-full gap-4">
        <h3 class="text-2xl font-bold flex items-center gap-2">
          <%= @title %>
          <.notification_bubble notification_count={@notification_count} />
        </h3>
      </div>
      <div class={"mb-2 #{@inner_block_classes}"}>
        <%= render_slot(@inner_block) %>
      </div>
      <div class="flex items-center gap-4 mt-auto">
        <%= if @button_action && @button_text do %>
          <button class="btn-tertiary border border-base-300/25 py-2 px-4 md:mt-0 flex-wrap whitespace-nowrap flex-shrink-0 text-sm" type="button" phx-click={@button_action}><%= @button_text %></button>
        <% end %>
        <%= if @link_action && @link_text do %>
          <button class="underline text-blue-planning-300 inline-block text-sm" type="button" phx-click={@link_action} phx-value-tab={@link_value} phx-value-to={@redirect_route}><%= @link_text %></button>
        <% end %>
      </div>
    </div>
    """
  end

  def notification_bubble(assigns) do
    assigns =
      Enum.into(assigns, %{
        notification_count: nil,
        classes: nil
      })

    ~H"""
    <%= if @notification_count && @notification_count !== 0 do %>
      <span {testid("badge")} class={"text-xs bg-red-sales-300 text-white leading-none rounded-full flex items-center justify-center px-2 pt-0.5 pb-1 #{@classes}"}><%= @notification_count %></span>
    <% end %>
    """
  end

  def thread_card(assigns) do
    ~H"""
    <div {testid("thread-card")} phx-click="open-thread" phx-value-id={@id} phx-value-type={@type} class="flex justify-between border-b cursor-pointer first:pt-0 py-3">
      <div class="">
        <div class="flex items-center">
          <div class="text-xl line-clamp-1 font-bold"><%= @title %></div>
          <%= if @unread do %>
            <span {testid("new-badge")} class="mx-4 px-2 py-0.5 text-xs rounded bg-blue-planning-300 text-white">New</span>
          <% end %>
        </div>
        <div class="line-clamp-1 font-semibold py-0.5 text-base-250"><%= @subtitle %></div>
        <%= if @message do %>
          <div class="line-clamp-1 text-base-250"><%= @message |> String.replace(["<p>", "</p>"], "") %></div>
        <% end %>
      </div>
      <div class="relative flex flex-shrink-0">
        <%= @date %>
        <.icon name="forth" class="sm:hidden absolute top-1.5 -right-6 w-4 h-4 stroke-current text-base-300 stroke-2" />
      </div>
    </div>
    """
  end

  defp assign_inbox_threads(%{assigns: %{current_user: current_user}} = socket) do
    job_query = Job.for_user(current_user) |> ClientMessage.unread_messages()

    message_query =
      from(message in job_query,
        distinct: message.job_id,
        order_by: [desc: message.inserted_at]
      )

    inbox_threads =
      from(message in subquery(message_query), order_by: [desc: message.inserted_at], limit: 1)
      |> Repo.all()
      |> Repo.preload(job: :client)
      |> Enum.map(fn message ->
        %{
          id: message.job_id,
          title: message.job.client.name,
          subtitle: Job.name(message.job),
          message: message.body_text,
          date: strftime(current_user.time_zone, message.inserted_at, "%-m/%-d/%y"),
          type: thread_type(message)
        }
      end)

    socket
    |> assign(:inbox_threads, inbox_threads)
  end

  defp tabs_list(_socket) do
    [
      {true,
       %{
         name: "To do",
         concise_name: "todo",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }},
      {false,
       %{
         name: "Finish Setup",
         concise_name: "finish-setup",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }},
      {true,
       %{
         name: "Clients",
         concise_name: "clients",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }},
      {true,
       %{
         name: "Leads",
         concise_name: "leads",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }},
      {true,
       %{
         name: "Jobs",
         concise_name: "jobs",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }},
      {true,
       %{
         name: "Galleries",
         concise_name: "galleries",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }},
      {true,
       %{
         name: "Booking Events",
         concise_name: "booking-events",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }},
      {true,
       %{
         name: "Packages",
         concise_name: "packages",
         action: "change-tab",
         redirect_route: nil,
         notification_count: nil
       }}
    ]
  end

  defp assign_tab_data(
         %{assigns: %{current_user: current_user}} = socket,
         tab
       ) do
    %{organization: organization} = Repo.preload(current_user, :organization)

    case tab do
      "clients" ->
        socket |> assign(:clients, Clients.get_recent_clients(current_user))

      "leads" ->
        socket |> assign(:leads, Jobs.get_recent_leads(current_user))

      "jobs" ->
        socket |> assign(:jobs, Jobs.get_recent_jobs(current_user))

      "galleries" ->
        socket |> assign(:galleries, Galleries.get_recent_galleries(current_user))

      "booking-events" ->
        socket
        |> assign(
          :booking_events,
          BookingEvents.get_booking_events(organization.id,
            filters: %{sort_by: :inserted_at, sort_direction: :desc}
          )
          |> Enum.filter(fn b_e -> Enum.any?(b_e.dates, &(&1["date"] not in [nil, ""])) end)
          |> Enum.map(fn booking_event ->
            BEShared.put_url_booking_event(booking_event, organization, socket)
          end)
        )

      "packages" ->
        socket |> assign(:packages, Packages.get_recent_packages(current_user))

      "finish-setup" ->
        socket
        |> assign(
          :org_stripe_card,
          OrganizationCard.get_org_stripe_card(current_user.organization_id)
        )

      _ ->
        socket
    end
  end

  def maybe_show_success_subscription(socket, %{
        "session_id" => "" <> session_id
      }) do
    if connected?(socket),
      do: send(self(), {:stripe_session_id, session_id})

    socket
    |> assign(:stripe_subscription_status, :loading)
  end

  def maybe_show_success_subscription(socket, _), do: socket

  def assign_counts(%{assigns: %{current_user: current_user}} = socket) do
    socket
    |> assign(
      inbox_count: inbox_count(current_user),
      client_count: client_count(current_user)
    )
  end

  def time_of_day_greeting(%User{time_zone: time_zone} = user) do
    greeting =
      case DateTime.now(time_zone) do
        {:ok, %{hour: hour}} when hour in 5..11 -> "Good Morning"
        {:ok, %{hour: hour}} when hour in 12..17 -> "Good Afternoon"
        {:ok, %{hour: hour}} when hour in 18..23 -> "Good Evening"
        _ -> "Hello"
      end

    "#{greeting}, #{User.first_name(user)}!"
  end

  def assign_attention_items(
        %{
          assigns: %{
            current_user: %{organization_id: organization_id} = current_user
          }
        } = socket
      ) do
    subscription = current_user |> Subscriptions.subscription_ending_soon_info()
    orders = get_all_proofing_album_orders(organization_id) |> Map.new(&{&1.id, &1})

    organization_id
    |> OrganizationCard.list()
    |> Enum.reduce([], fn
      %{card: %{concise_name: "open-user-settings", body: body}} = org_card, acc ->
        data = build_data(subscription)
        acc ++ [add(org_card, Utils.render(body, data))]

      %{card: %{concise_name: "proofing-album-order", body: body}} = org_card, acc ->
        orders
        |> Map.get(org_card.data.order_id)
        |> then(fn
          %{gallery: %{job: %{client: client}}} = order ->
            buttons = build_buttons(socket, org_card.card.buttons, order)

            acc ++ [add(org_card, Utils.render(body, %{"name" => client.name}), buttons)]

          _ ->
            acc
        end)

      org_card, acc ->
        acc ++ [org_card]
    end)
    |> Enum.sort_by(& &1.card.index)
    |> Enum.map(fn %{card: %{concise_name: concise_name}} = org_card ->
      case concise_name do
        card_concise_name
        when card_concise_name in @card_concise_name_list ->
          map_card_to_action_logic(
            org_card,
            subscription,
            socket
          )

        _ ->
          {true, org_card}
      end
    end)
    |> then(
      &(socket
        |> assign(
          attention_items: &1,
          should_attention_items_overflow: Enum.count(&1) > 4
        ))
    )
  end

  defp recent_data(assigns) do
    count =
      if Map.has_key?(assigns.data, :client_link_hash),
        do: Enum.count(assigns.data.orders),
        else: Map.get(assigns.data, :booking_count, 0)

    assigns = assign(assigns, count: count)

    ~H"""
      <div class="flex flex-wrap w-full md:w-auto">
        <div class="flex flex-col p-2 gap-2 md:gap-4 w-full md:flex-row grow">
          <%= if Map.has_key?(@data, :thumbnail_url) do %>
            <.link navigate={~p"/booking-events/#{@data.id}"}>
              <.blurred_thumbnail class="rounded-lg h-full items-center flex flex-col w-[100px] h-[65px] bg-base-200" url={@data.thumbnail_url} />
            </.link>
          <% else %>
              <%= if @data.cover_photo do %>
              <.link navigate={(if Map.has_key?(assigns.data, :client_link_hash), do: ~p"/galleries/#{@data.id}?#{%{is_mobile: false}}", else: ~p"/booking-events/#{@data.id}")}>
                <div class="rounded-lg float-left w-[100px] min-h-[65px]" style={"background-image: url('#{if Map.has_key?(@data, :client_link_hash), do: cover_photo_url(@data), else: @data.thumbnail_url}'); background-repeat: no-repeat; background-size: cover; background-position: center;"}></div>
              </.link>
            <% else %>
              <div class="rounded-lg h-full p-2 items-center flex flex-col w-[100px] h-[65px] bg-base-200">
                <div class="flex justify-center h-full items-center">
                  <.icon name="photos-2" class="inline-block w-3 h-3 text-base-250"/>
                </div>
                <div class="mt-1 text-[8px] text-base-250 text-center h-full">
                  <span>Edit your gallery to upload a cover photo</span>
                </div>
              </div>
            <% end %>
          <% end %>

          <div class="flex flex-col w-2/3 text-sm">
            <div class={"font-bold w-full"}>
              <.link navigate={(if Map.has_key?(assigns.data, :client_link_hash), do: ~p"/galleries/#{@data.id}?#{%{is_mobile: false}}", else: ~p"/booking-events/#{@data.id}")}>
                <span class="w-full text-blue-planning-300 underline">
                  <%= if String.length(@data.name) < 30 do
                    @data.name
                  else
                    "#{@data.name |> String.slice(0..18)} ..."
                  end %>
                </span>
              </.link>
            </div>
            <div class="text-base-250 font-normal mb-2">
              <%= unless Map.has_key?(assigns.data, :client_link_hash) do %>
                <%= @data.dates |> hd() |> Map.get("date") |> BEShared.convert_date_string_to_date() |> convert_date_format() %>
                <%= if !Map.has_key?(assigns.data, :client_link_hash) do %> - <%= @count %> <%= if @count == 1, do: "booking", else: "bookings" %> so far<% end %>
              <% end %>
            </div>
            <div class="flex md:gap-2 gap-3">
              <button {testid("copy-link")} id={"copy-link-#{@data.id}"} class={classes("flex  w-full md:w-auto items-center justify-center text-center px-1 py-0.5 font-sans border rounded-lg btn-tertiary text-blue-planning-300 flex-shrink-0", %{"pointer-events-none text-gray-300 border-gray-200" => @data.status in [:archive, :disabled]})} data-clipboard-text={if Map.has_key?(@data, :client_link_hash), do: clip_board(@socket, @data), else: @data.url} phx-hook="Clipboard">
                <.icon name="anchor" class={classes("w-2 h-2 fill-current text-blue-planning-300 inline mr-2", %{"text-gray-300" => @data.status in [:archive, :disabled]})} />
                Copy link
                <div class="hidden p-1 text-sm rounded shadow" role="tooltip">
                  Copied!
                </div>
              </button>
            </div>
          </div>
        </div>
      </div>
    """
  end

  defp map_card_to_action_logic(
         %{card: %{concise_name: concise_name}} = org_card,
         subscription,
         %{
           assigns: %{
             stripe_status: stripe_status,
             current_user: current_user
           }
         }
       ) do
    params = %{
      "send-confirmation-email" => {!User.confirmed?(current_user), org_card},
      "open-user-settings" => {!subscription.hidden?, org_card},
      "getting-started-todoplace" =>
        {Application.get_env(:todoplace, :intercom_id) != nil, org_card},
      "set-up-stripe" => {stripe_status != :charges_enabled, org_card},
      "open-billing-portal" =>
        {Todoplace.Invoices.pending_invoices?(current_user.organization_id), org_card},
      "missing-payment-method" =>
        {!Todoplace.Subscriptions.subscription_payment_method?(current_user), org_card},
      "black-friday" => {Subscriptions.interval(current_user.subscription) == "month", org_card}
    }

    case params |> Map.fetch(concise_name) do
      {:ok, action} -> action
      :error -> {true, org_card}
    end
  end

  defp build_data(subscription) do
    %{
      "days_left" => ngettext("1 day", "%{count} days", Map.get(subscription, :days_left, 0)),
      "subscription_end_at" => Map.get(subscription, :subscription_end_at, nil)
    }
  end

  defp build_buttons(socket, [button_1, button_2], %{
         album: album,
         number: number,
         gallery: gallery
       }) do
    [
      Map.put(
        button_1,
        :link,
        ~p"/galleries/#{gallery.id}/albums/#{album.id}"
      ),
      Map.put(
        button_2,
        :link,
        url(~p"/gallery/#{gallery.client_link_hash}/orders/#{number}/csv-lightroom")
      )
    ]
  end

  defp add(%{card: card} = org_card, body, buttons \\ nil) do
    card = if buttons, do: %{card | buttons: buttons}, else: card

    %{org_card | card: %{card | body: body}}
  end

  def card_buttons(%{concise_name: _, buttons: _} = assigns) do
    ~H"""
    <%= case @concise_name do %>
      <% "set-up-stripe" -> %>
        <.live_component module={TodoplaceWeb.StripeOnboardingComponent} id={:stripe_onboarding}
          error_class="text-center"
          class={"#{List.first(@buttons).class} text-sm w-full py-2 mt-2"}
          current_user={@current_user}
          return_url={url(~p"/home")}
          org_card_id={@org_card_id}
          stripe_status={@stripe_status} />
      <% _ -> %>
      <span class="flex-shrink-0 flex flex-col justify-between" data-status="viewed" id={"#{@org_card_id}"} phx-hook="CardStatus">
        <.card_button buttons={@buttons} />
      </span>
    <% end %>
    """
  end

  def card_button(%{buttons: [%{external_link: external_link} = button]} = assigns)
      when not is_nil(external_link) do
    assigns = assign(assigns, external_link: external_link, button: button)

    ~H"""
    <.custom_link
    link={@external_link}
    class={@button.class}
    label={@button.label}
    target="_blank"
    rel="noopener noreferrer" />
    """
  end

  def card_button(%{buttons: [%{link: link} = button]} = assigns) when not is_nil(link) do
    assigns = assign(assigns, link: link, button: button)

    ~H"""
    <.custom_link link={@link} class={@button.class} label={@button.label} />
    """
  end

  def card_button(%{buttons: [%{action: action} = button]} = assigns) when not is_nil(action) do
    assigns = assign(assigns, action: action, button: button)

    ~H"""
    <button type="button" phx-click={@action} phx-click="sss" class={"#{@button.class} text-sm w-full py-2 mt-2"}>
      <%= @button.label %>
    </button>
    """
  end

  def card_button(%{buttons: [button_1, button_2]} = assigns) do
    assigns = assign(assigns, button_1: button_1, button_2: button_2)

    ~H"""
    <div class="flex gap-4">
     <.card_button buttons={[@button_1]} />
     <.card_button buttons={[@button_2]} />
    </div>
    """
  end

  def custom_link(assigns) do
    assigns = Enum.into(assigns, %{target: "", rel: ""})

    ~H"""
     <a href={@link} class={"#{@class} text-center text-sm w-full py-2 mt-2"} target={@target} rel={@rel}>
        <%= @label %>
      </a>
    """
  end

  def card(assigns) do
    assigns =
      assigns
      |> Map.put(:attrs, Map.drop(assigns, ~w(class icon color inner_block badge)a))
      |> Enum.into(%{badge: nil, hint_content: nil})

    ~H"""
    <li class={"relative #{Map.get(assigns, :class)}"} {@attrs}>
      <%= if @badge do %>
          <div {testid "badge"} class={classes("absolute -top-2.5 right-5 leading-none w-5 h-5 rounded-full pb-0.5 flex items-center justify-center text-xs", %{"bg-base-300 text-white" => @badge > 0, "bg-gray-300" => @badge == 0})}>
          <%= if @badge > 0, do: @badge %>
        </div>
      <% end %>
      <div class={"border hover:border-#{@color} h-full rounded-lg bg-#{@color} overflow-hidden"}>
        <div class="h-full p-5 ml-3 bg-white">
            <h1 class="text-lg font-bold">
            <.icon name={@icon} width="23" height="20" class={"inline-block mr-2 rounded-sm fill-current text-#{@color}"} />
            <%= @title %> <%= if @hint_content do %><.tooltip id="tooltip-#{@title}" content={@hint_content} /><% end %>
          </h1>
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </li>
    """
  end

  def recents_card(assigns) do
    assigns =
      Enum.into(assigns, %{
        class: "",
        color: "blue-planning-300"
      })

    ~H"""
    <div {testid("card-#{@title}")} class={"flex overflow-hidden border border-base-200 rounded-lg #{@class}"}>
      <div class={"w-3 flex-shrink-0 border-r rounded-l-lg bg-#{@color}"} />
      <div class="flex flex-col w-full p-4">
        <div class="flex flex-wrap justify-between items-center mb-2 w-full gap-0 md:gap-10">
          <h3 class={"mb-2 mr-4 text-xl font-bold text-black"}><%= @title %></h3>
          <div class="flex flex-row items-center justify-between">
            <button type="button" class="md:order-1 order-2 link px-4 mb-2 md:mb-0" phx-click={@view_event} hidden={@hidden}>
              View all
            </button>
            <button type="button" class="md:order-2 order-1 font-bold btn-tertiary py-2" phx-click={@add_event}>
              <%= @button_title %>
            </button>
          </div>
        </div>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def subscription_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-[200] flex items-center justify-center bg-black/60">
      <div class="rounded-lg modal no-pad sm:max-w-5xl">
        <div class="p-6 sm:p-8">
          <div class="sm:max-w-3xl mb-2 sm:mb-8">
            <h1 class="text-xl sm:text-4xl font-semibold">Your subscription has expired</h1>
            <p class="pt-2 sm:pt-4 text-base-250 sm:text-lg">We’ve missed you and are very excited to welcome you back to take advantage of all the new features we’ve been working on. Select your plan below:</p>
          </div>
          <div class="mt-4 grid grid-cols-1 md:grid-cols-2 gap-8">
            <%= for subscription_plan <- Subscriptions.subscription_plans() |> Enum.reverse() do %>
              <%= case subscription_plan do %>
                <% %{recurring_interval: "month"} -> %>
                  <.subscription_modal_card
                    button_class="btn-tertiary"
                    subscription_plan={subscription_plan}
                    headline="Monthly"
                    price={"#{subscription_plan.price |> Money.to_string(fractional_unit: false)} monthly"}
                    price_secondary={"(#{subscription_plan.price |> Money.multiply(12) |> Money.to_string(fractional_unit: false)}/year)"}
                    interval={subscription_plan.recurring_interval}
                    body="You get everything in the monthly plan PLUS exclusive access to Todoplace’s Business Mastermind with classes and so much more"
                  />
                <% %{recurring_interval: "year"} -> %>
                  <.subscription_modal_card
                    class="bg-blue-planning-300 text-white"
                    subscription_plan={subscription_plan}
                    headline="Yearly"
                    price={"#{subscription_plan.price |> Money.to_string(fractional_unit: false)} yearly"}
                    price_secondary={"Best value!"}
                    interval={subscription_plan.recurring_interval}
                    body="You get everything in the monthly plan PLUS exclusive access to Todoplace’s Business Mastermind with classes and so much more"
                  />
                <% _ -> %>
              <% end %>
            <% end %>
          </div>
          <div class="flex justify-end mt-6">
            <.form :let={f} for={@promotion_code_changeset} phx-change="validate-promo-code" id="modal-form" phx-submit="save-promo-code">
              <%= hidden_inputs_for f %>
              <.inputs_for :let={onboarding} field={f[:onboarding]}>
                <details class="group" open={@promotion_code_open} {testid("promo-code")}>
                  <summary class={classes("cursor-pointer underline flex items-center", %{"text-blue-planning-300" => Enum.empty?(onboarding.errors), "text-red-sales-300" => onboarding.errors })} phx-click="handle-promotion-code-toggle">
                  <%= if Enum.empty?(onboarding.errors), do: "Add a promo code", else: "Fix promo code" %>
                    <.icon name="down" class="w-4 h-4 stroke-current stroke-2 ml-2 group-open:rotate-180" />
                  </summary>
                  <%= hidden_inputs_for onboarding %>
                  <%= labeled_input onboarding, :promotion_code, label: "Applies to monthly or yearly", type: :text_input, phx_debounce: 500, min: 0, placeholder: "enter promo code…", class: "mb-3" %>
                </details>
              </.inputs_for>
            </.form>
          </div>
        </div>
        <div class="bg-gray-100 p-6 sm:p-8">
          <div class="grid grid-cols-1 sm:grid-cols-2 items-center gap-2 sm:gap-8">
            <div>
              <img src="/images/subscription-modal.png" alt="An image of the Todoplace application" loading="lazy" />
              <%= link("Logout", to: ~p"/users/log_out", method: :delete, class: "underline text-base-250 inline-block mt-2") %>
            </div>
            <div>
              <h5 class="font-bold mb-1">Everything included:</h5>
              <ul class="text-base-250 space-y-1 text-sm">
                <%= for feature <- subscription_modal_feature_list() do %>
                  <li>
                    <.icon name="checkcircle" class="inline-block w-4 h-4 mr-2 fill-current text-blue-planning-300" />
                    <%= feature %>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp subscription_modal_feature_list,
    do: [
      "Streamlined client booking",
      "Beautiful client galleries",
      "Easy invoicing, contracts and booking",
      "Automated email marketing tools",
      "Pricing assistance",
      "Integrated inbox and client messaging",
      "Unlimited storage",
      "100% photographer-profit merchandise sales",
      "Access to Todoplace's Business Mastermind (Yearly only)"
    ]

  defp subscription_modal_card(assigns) do
    assigns =
      assigns
      |> Enum.into(%{class: nil, button_class: "btn-primary"})

    ~H"""
    <div class={"p-2 md:p-4 border rounded-lg #{@class}"}>
      <div class="flex gap-2 gap-4 sm:gap-0 flex-wrap items-center justify-between">
        <div>
          <h4 class="text-xl md:text-3xl font-bold mb-2"><%= @headline %></h4>
          <p class="font-bold"><%= @price %></p>
          <p class="opacity-60"><%= @price_secondary %></p>
        </div>
        <button class={@button_class} type="button" phx-click="subscription-checkout" phx-value-interval={@interval}>
          Select plan
        </button>
      </div>
      <hr class="my-2 md:my-4 opacity-50" />
      <p class="text-xs md:text-sm opacity-75 md:opacity-60"><%= @body %></p>
    </div>
    """
  end

  defp client_count(user) do
    Clients.find_count_by(user: user)
  end

  defp inbox_count(user) do
    Job.for_user(user)
    |> ClientMessage.unread_messages()
    |> Repo.aggregate(:count)
  end

  def assign_stripe_status(%{assigns: %{current_user: current_user}} = socket) do
    socket |> assign(stripe_status: Payments.status(current_user))
  end

  def subscribe_inbound_messages(%{assigns: %{current_user: current_user}} = socket) do
    Phoenix.PubSub.subscribe(
      Todoplace.PubSub,
      "inbound_messages:#{current_user.organization_id}"
    )

    socket
  end

  defp welcome_modal_state(%{assigns: %{current_user: current_user}} = socket) do
    socket
    |> close_modal
    |> assign(
      current_user:
        Todoplace.Onboardings.save_intro_state(current_user, "intro_dashboard_modal", "completed")
    )
  end

  defp build_subscription_link(
         %{
           assigns: %{
             current_user: current_user,
             promotion_code_changeset: promotion_code_changeset
           }
         } = socket,
         interval,
         promotion_code_id
       ) do
    case Subscriptions.checkout_link(
           current_user,
           interval,
           success_url: "#{url(~p"/home")}?session_id={CHECKOUT_SESSION_ID}",
           cancel_url: url(~p"/home"),
           promotion_code: promotion_code_id
         ) do
      {:ok, url} ->
        promotion_code_changeset
        |> Map.put(:action, :update)
        |> Repo.update!()

        socket |> redirect(external: url) |> noreply()

      {:error, error} ->
        Logger.warning("Error redirecting to Stripe: #{inspect(error)}")
        socket |> put_flash(:error, "Couldn't redirect to Stripe. Please try again") |> noreply()
    end
  end

  defp build_promotion_code_changeset(
         %{assigns: %{current_user: user}},
         params,
         action
       ) do
    user
    |> Onboardings.user_update_promotion_code_changeset(params)
    |> Map.put(:action, action)
  end

  defp assign_promotion_code_changeset(
         %{assigns: %{promotion_code: promotion_code}} = socket,
         params \\ %{}
       ) do
    params =
      Enum.into(params, %{
        "onboarding" => %{
          "promotion_code" => promotion_code
        }
      })

    socket
    |> assign(
      :promotion_code_changeset,
      build_promotion_code_changeset(socket, params, :validate)
    )
  end

  defp build_invoice_link(
         %{
           assigns: %{
             current_user: current_user,
             promotion_code: promotion_code
           }
         } = socket
       ) do
    discounts_data =
      if promotion_code,
        do: %{
          discounts: [
            %{
              coupon: Subscriptions.maybe_return_promotion_code_id?(promotion_code)
            }
          ]
        },
        else: %{}

    stripe_params =
      %{
        client_reference_id: "blackfriday_2023",
        cancel_url: url(~p"/home"),
        success_url:
          "#{url(~p"/home")}?pre_purchase=true&checkout_session_id={CHECKOUT_SESSION_ID}",
        billing_address_collection: "auto",
        customer: Subscriptions.user_customer_id(current_user),
        line_items: [
          %{
            price_data: %{
              currency: "USD",
              unit_amount: 35_000,
              product_data: %{
                name: "Holiday Sale 2023",
                description: "Pre purchase your next year of Todoplace!"
              },
              tax_behavior: "exclusive"
            },
            quantity: 1
          }
        ]
      }
      |> Map.merge(discounts_data)

    case Payments.create_session(stripe_params, []) do
      {:ok, %{url: url}} ->
        socket |> redirect(external: url) |> noreply()

      {:error, error} ->
        Logger.warning("Error redirecting to Stripe: #{inspect(error)}")
        socket |> put_flash(:error, "Couldn't redirect to Stripe. Please try again") |> noreply()
    end
  end

  defp thread_type(%{job_id: nil}), do: :client
  defp thread_type(%{job_id: _job_id}), do: :job

  defp convert_date_format(nil), do: nil
  defp convert_date_format(date), do: date |> Calendar.strftime("%m/%d/%y") |> String.trim("0")

  defdelegate get_all_proofing_album_orders(organization_id), to: Orders
end
