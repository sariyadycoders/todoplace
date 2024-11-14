defmodule TodoplaceWeb.Live.User.Welcome.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view

  import TodoplaceWeb.Live.User.Welcome.AccordionComponent, only: [youtube_video: 1]

  alias TodoplaceWeb.{Shared.SelectionPopupModal, Live.Calendar.BookingEvents.Index}

  alias Todoplace.{
    Onboardings.Welcome,
    Contract,
    Contracts,
    Questionnaire,
    Subscriptions
  }

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(:main_class, "bg-gray-100")
    |> push_event("confetti", %{should_fire: true})
    |> assign_welcome_states_by_group()
    |> assign_organization()
    |> assign_stripe_status()
    |> ok()
  end

  @impl true
  def handle_event("upload-logo", %{}, %{assigns: %{organization: organization}} = socket) do
    socket
    |> push_event("intercom", %{event: "Upload Logo"})
    |> TodoplaceWeb.Brand.BrandLogoComponent.open(organization)
    |> noreply()
  end

  @impl true
  def handle_event("view-global-gallery-settings", _, socket) do
    socket
    |> push_event("intercom", %{event: "Gallery Settings"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/galleries/settings?#{%{section: "watermark"}}"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "create-contract",
        %{},
        %{assigns: %{organization: organization, current_user: current_user} = assigns} = socket
      ) do
    socket
    |> push_event("intercom", %{event: "Create Contract"})
    |> assign_new(:contract, fn ->
      default_contract = Contracts.get_default_template()

      content =
        Contracts.default_contract_content(default_contract, current_user, TodoplaceWeb.Helpers)

      %Contract{
        content: content,
        contract_template_id: default_contract.id,
        organization_id: organization.id
      }
    end)
    |> TodoplaceWeb.ContractTemplateComponent.open(
      Map.merge(Map.take(assigns, [:contract, :current_user]), %{
        state: :create
      })
    )
    |> noreply()
  end

  @impl true
  def handle_event("view-contracts", _, socket) do
    socket
    |> push_event("intercom", %{event: "View Contracts"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/contracts"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "create-questionnaire",
        %{},
        %{assigns: %{organization: organization, current_user: _current_user} = assigns} = socket
      ) do
    assigns =
      Map.merge(assigns, %{
        questionnaire: %Questionnaire{organization_id: organization.id}
      })

    socket
    |> push_event("intercom", %{event: "Create Questionnaire"})
    |> TodoplaceWeb.QuestionnaireFormComponent.open(
      Map.merge(Map.take(assigns, [:questionnaire, :current_user]), %{state: :create})
    )
    |> noreply()
  end

  @impl true
  def handle_event(
        "create-gallery",
        %{
          "group" => group,
          "slug" => slug,
          "id" => id
        },
        %{assigns: assigns} = socket
      ) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: id,
      group: group,
      slug: slug
    )

    socket
    |> push_event("intercom", %{event: "Create Gallery"})
    |> open_modal(
      TodoplaceWeb.GalleryLive.CreateComponent,
      Map.take(assigns, [:current_user, :currency])
    )
    |> noreply()
  end

  @impl true
  def handle_event(
        "create-booking-event",
        %{},
        %{assigns: _assigns} = socket
      ) do
    socket
    |> push_event("intercom", %{event: "Create Booking Event"})
    |> SelectionPopupModal.open(%{
      heading: "Create a Booking Event",
      title_one: "Single Event",
      subtitle_one: "Best for a single weekend or a few days you’d like to fill.",
      icon_one: "calendar-add",
      btn_one_event: "create-single-event",
      title_two: "Repeating Event",
      subtitle_two: "Best for an event you’d like to run every week, weekend, every month, etc.",
      icon_two: "calendar-repeat",
      btn_two_event: "create-repeating-event"
    })
    |> noreply()
  end

  @impl true
  def handle_event("view-questionnaires", _, socket) do
    socket
    |> push_event("intercom", %{event: "View Questionnaires"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/questionnaires"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "view-automations",
        %{
          "group" => group,
          "slug" => slug,
          "id" => id
        },
        socket
      ) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: id,
      group: group,
      slug: slug
    )

    socket
    |> push_event("intercom", %{event: "View Automations"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/email-automations"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "create-package",
        %{},
        %{assigns: assigns} = socket
      ) do
    socket
    |> push_event("intercom", %{event: "Create Package"})
    |> open_modal(
      TodoplaceWeb.PackageLive.WizardComponent,
      assigns |> Map.take([:current_user, :currency])
    )
    |> noreply()
  end

  @impl true
  def handle_event("view-packages", _, socket) do
    socket
    |> push_event("intercom", %{event: "View Packages"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/package_templates"
    })
    |> noreply()
  end

  @impl true
  def handle_event("enable-offline-payments", _, socket) do
    socket
    |> push_event("intercom", %{event: "View Payment Settings"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/finance"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "view-embed",
        %{
          "group" => group,
          "slug" => slug,
          "id" => id
        },
        %{assigns: %{current_user: %{organization: organization}}} = socket
      ) do
    embed_code = Todoplace.Profiles.embed_code(organization)

    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: id,
      group: group,
      slug: slug
    )

    socket
    |> push_event("intercom", %{event: "View Embed"})
    |> open_modal(TodoplaceWeb.Live.Profile.CopyContactFormComponent, %{embed_code: embed_code})
    |> noreply()
  end

  @impl true
  def handle_event(
        "contact-todoplace-embed",
        _,
        socket
      ) do
    socket
    |> push_event("intercom", %{event: "Contact Todoplace Embed"})
    |> noreply()
  end

  @impl true
  def handle_event(
        "bulk-upload-contacts",
        %{
          "group" => group,
          "slug" => slug,
          "id" => id
        },
        socket
      ) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: id,
      group: group,
      slug: slug
    )

    socket
    |> push_event("intercom", %{event: "Open Bulk Contact Upload"})
    |> noreply()
  end

  @impl true
  def handle_event("calendar-sync", _, socket) do
    socket
    |> push_event("intercom", %{event: "View Calendar Sync"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/calendar/settings?#{%{_action: "open-connect"}}"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "finance-options",
        %{
          "group" => group,
          "slug" => slug,
          "id" => id
        },
        socket
      ) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: id,
      group: group,
      slug: slug
    )

    socket
    |> push_event("intercom", %{event: "View Finance Options"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/finance"
    })
    |> noreply()
  end

  @impl true
  def handle_event("add-payment-method", _, %{assigns: %{current_user: current_user}} = socket) do
    {:ok, url} =
      Subscriptions.billing_portal_link(
        current_user,
        url(~p"/users/welcome")
      )

    socket
    |> push_event("intercom", %{event: "Add Payment Method"})
    |> push_event("ViewClientLink", %{
      "url" => url
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "automation-settings",
        %{
          "group" => group,
          "slug" => slug,
          "id" => id
        },
        socket
      ) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: id,
      group: group,
      slug: slug
    )

    socket
    |> push_event("intercom", %{event: "View Automations"})
    |> push_event("ViewClientLink", %{
      "url" => ~p"/email-automations"
    })
    |> noreply()
  end

  @impl true
  def handle_info(
        {:is_complete_update, %{is_complete: is_complete, is_success: is_success}},
        %{assigns: %{current_user: current_user, live_action: _live_action}} = socket
      ) do
    if is_success do
      socket
      |> put_flash(:success, if(is_complete, do: "Marked complete!", else: "Marked incomplete!"))
      |> push_event("confetti", %{should_fire: is_complete == true})
      |> push_event("sidebar:update_onboarding_percentage", %{
        onboarding_percentage: Welcome.get_percentage_completed_count(current_user)
      })
    else
      socket
      |> put_flash(:error, "Something went wrong! Try again.")
    end
    |> noreply()
  end

  @impl true
  def handle_info({:update, %{package: _package}}, socket) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: "8",
      group: "quick-start",
      slug: "create-package"
    )

    socket |> noreply()
  end

  @impl true
  def handle_info({:update, %{questionnaire: _questionnaire}}, socket) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: "7",
      group: "quick-start",
      slug: "create-questionnaire"
    )

    socket |> noreply()
  end

  @impl true
  def handle_info({:update, %{contract: _contract}}, socket) do
    send_update(TodoplaceWeb.Live.User.Welcome.AccordionComponent,
      id: "6",
      group: "quick-start",
      slug: "create-contract"
    )

    socket |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "create-single-event"} = message,
        socket
      ),
      do: Index.handle_info(message, socket)

  @impl true
  def handle_info(
        {:confirm_event, "create-repeating-event"} = message,
        socket
      ),
      do: Index.handle_info(message, socket)

  defp assign_welcome_states_by_group(%{assigns: %{current_user: current_user}} = socket) do
    welcome_states =
      current_user
      |> Welcome.get_all_welcome_states_by_user()
      |> Welcome.group_by_welcome_group()

    socket
    |> assign(:welcome_states, welcome_states)
  end

  defp assign_organization(%{assigns: %{current_user: current_user}} = socket) do
    socket |> assign_organization(current_user.organization)
  end

  defp assign_organization(socket, organization) do
    socket
    |> assign(:organization, organization)
  end

  defp assign_stripe_status(%{assigns: %{current_user: current_user}} = socket) do
    socket |> assign(stripe_status: Todoplace.Payments.status(current_user))
  end
end
