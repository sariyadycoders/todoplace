defmodule TodoplaceWeb.LeadLive.Show do
  @moduledoc false
  use TodoplaceWeb, :live_view
  require Logger

  alias Todoplace.{
    Job,
    Repo,
    Payments,
    BookingProposal,
    Notifiers.ClientNotifier,
    Questionnaire,
    Contracts,
    Messages,
    EmailAutomations,
    EmailAutomationSchedules,
    Utils
  }

  alias TodoplaceWeb.JobLive

  import TodoplaceWeb.JobLive.Shared,
    only: [
      is_manual_toggle?: 1,
      get_job_email_by_pipeline: 2,
      get_email_body_subject: 5,
      assign_job: 2,
      assign_proposal: 1,
      assign_disabled_copy_link: 1,
      history_card: 1,
      package_details_card: 1,
      finance_details_section: 1,
      client_details_section: 1,
      client_documents_section: 1,
      inbox_section: 1,
      view_title: 1,
      finances_section: 1,
      shoot_details_section: 1,
      validate_payment_schedule: 1,
      notes_editor: 1,
      tabs_list: 1
    ]

  @impl true
  def mount(
        %{"id" => job_id} = assigns,
        _session,
        %{assigns: %{current_user: _current_user}} = socket
      ) do
    socket
    |> assign_stripe_status()
    |> assign(:main_class, "bg-gray-100")
    |> assign(:tabs, tabs_list(nil))
    |> assign(:tab_active, "overview")
    |> assign_tab_data("overview")
    |> assign(include_questionnaire: true)
    |> assign(:type, %{singular: "lead", plural: "leads"})
    |> assign(:request_from, assigns["request_from"])
    |> assign_job(job_id)
    |> assign(:request_from, assigns["request_from"])
    |> assign(:collapsed_sections, [])
    |> assign_emails_count(job_id)
    |> subscribe_emails_count(job_id)
    |> then(fn %{assigns: assigns} = socket ->
      job = Map.get(assigns, :job)

      if(job) do
        payment_schedules = job |> Repo.preload(:payment_schedules) |> Map.get(:payment_schedules)

        socket
        |> assign(payment_schedules: payment_schedules)
        |> validate_payment_schedule()
        |> assign_disabled_copy_link()
      else
        socket
      end
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

  def handle_params(_, _, socket), do: noreply(socket)

  @impl true
  def handle_event(
        "copy-or-view-client-link",
        %{"action" => action},
        %{assigns: %{proposal: proposal, job: job}} = socket
      ) do
    if proposal do
      actions_event(socket, action, proposal)
    else
      socket
      |> upsert_booking_proposal()
      |> Repo.transaction()
      |> case do
        {:ok, %{proposal: proposal}} ->
          job =
            job
            |> Repo.preload([:client, :job_status, package: [:contract, :questionnaire_template]],
              force: true
            )

          socket =
            socket
            |> assign(proposal: proposal)
            |> assign(job: job, package: job.package)

          actions_event(socket, action, proposal)

        {:error, _} ->
          socket
          |> put_flash(:error, "Failed to fetch booking proposal. Please try again.")
      end
    end
    |> noreply()
  end

  @impl true
  def handle_event("add-package", %{}, %{assigns: assigns} = socket),
    do:
      socket
      |> open_modal(
        TodoplaceWeb.PackageLive.WizardComponent,
        assigns |> Map.take([:current_user, :job, :currency])
      )
      |> assign_disabled_copy_link()
      |> noreply()

  @impl true
  def handle_event("edit-package", %{}, %{assigns: %{proposal: proposal} = assigns} = socket) do
    if is_nil(proposal) || is_nil(proposal.signed_at) do
      socket
      |> TodoplaceWeb.ConfirmationComponent.open(%{
        confirm_event: "edit_package",
        confirm_label: "Yes, edit package details",
        subtitle:
          "Your proposal has already been created for the client-if you edit the package details, the proposal will update to reflect the changes you make.
          \nPRO TIP: Remember to communicate with your client on the changes!
          ",
        title: "Edit Package details?",
        icon: "warning-orange",
        payload: %{assigns: assigns}
      })
    else
      socket
      |> put_flash(:error, "Package can't be changed")
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "finish-proposal",
        %{},
        %{assigns: %{job: job, current_user: current_user, proposal: proposal}} = socket
      ) do
    {job, proposal} =
      if proposal do
        {job, proposal}
      else
        socket
        |> upsert_booking_proposal()
        |> Repo.transaction()
        |> case do
          {:ok, %{proposal: proposal}} ->
            job =
              job
              |> Repo.preload(
                [:client, :job_status, package: [:contract, :questionnaire_template]],
                force: true
              )

            {job, proposal}

          {:error, _} ->
            {job, proposal}
        end
      end

    pipeline = EmailAutomations.get_pipeline_by_state(:manual_booking_proposal_sent)
    email_by_state = get_job_email_by_pipeline(job.id, pipeline)

    last_completed_email =
      EmailAutomationSchedules.get_last_completed_email(
        :lead,
        nil,
        nil,
        job.id,
        pipeline.id,
        :manual_booking_proposal_sent,
        TodoplaceWeb.EmailAutomationLive.Shared
      )

    manual_toggle =
      if is_manual_toggle?(email_by_state) and is_nil(last_completed_email), do: true, else: false

    %{body_template: body_html, subject_template: subject} =
      get_email_body_subject(
        email_by_state,
        job,
        :manual_booking_proposal_sent,
        pipeline.id,
        :lead
      )

    body_html = Utils.normalize_body_template(body_html)

    socket
    |> assign(proposal: proposal)
    |> assign(job: job, package: job.package)
    |> TodoplaceWeb.ClientMessageComponent.open(%{
      composed_event: :proposal_message_composed,
      current_user: current_user,
      enable_size: true,
      enable_image: true,
      presets: [],
      body_html: body_html,
      subject: subject,
      client: Job.client(job),
      manual_toggle: manual_toggle,
      email_schedule: email_by_state
    })
    |> noreply()
  end

  def handle_event("open_lead_name_change", %{}, %{assigns: %{job: job}} = socket) do
    assigns = %{
      job: job,
      current_user: Map.take(socket.assigns, [:current_user])
    }

    socket
    |> open_modal(
      TodoplaceWeb.Live.Profile.EditNameSharedComponent,
      Map.put(assigns, :parent_pid, self())
    )
    |> noreply()
  end

  def handle_event("confirm_archive_lead", %{}, socket) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      close_label: "Cancel",
      confirm_event: "archive",
      confirm_label: "Yes, archive",
      icon: "warning-orange",
      title: "Are you sure you want to archive this lead?"
    })
    |> noreply()
  end

  def handle_event("confirm_unarchive_lead", %{}, socket) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      close_label: "Cancel",
      confirm_event: "unarchive-lead",
      confirm_label: "Yes, unarchive the lead",
      icon: "warning-orange",
      title: "Are you sure you want to unarchive this lead?"
    })
    |> noreply()
  end

  def handle_event("intro_js" = event, params, socket),
    do: TodoplaceWeb.LiveHelpers.handle_event(event, params, socket)

  @impl true
  def handle_event(
        "toggle-questionnaire",
        %{},
        %{assigns: %{include_questionnaire: include_questionnaire}} = socket
      ) do
    socket
    |> assign(:include_questionnaire, !include_questionnaire)
    |> noreply()
  end

  @impl true
  def handle_event(
        "open-questionnaire",
        %{},
        %{assigns: %{job: job, package: package}} = socket
      ) do
    socket
    |> TodoplaceWeb.BookingProposalLive.QuestionnaireComponent.open_modal_from_lead(job, package)
    |> noreply()
  end

  @impl true
  def handle_event(
        "edit-questionnaire",
        %{},
        %{assigns: %{current_user: current_user, package: package, job: job}} = socket
      ) do
    if is_nil(package.questionnaire_template) do
      template = Questionnaire.for_job(job) |> Repo.one()

      case maybe_insert_questionnaire(template, current_user, package) do
        {:ok, %{questionnaire_insert: questionnaire_insert}} ->
          socket
          |> open_questionnaire_modal(current_user, questionnaire_insert)

        {:error, _} ->
          socket
          |> put_flash(:error, "Failed to fetch questionnaire. Please try again.")
      end
    else
      socket
      |> open_questionnaire_modal(current_user, package.questionnaire_template)
    end
    |> noreply()
  end

  @impl true
  def handle_event("edit-contract", %{}, socket) do
    socket
    |> TodoplaceWeb.ContractFormComponent.open(
      Map.take(socket.assigns, [:package, :job, :current_user])
    )
    |> noreply()
  end

  @impl true
  def handle_event("change-tab", %{"tab" => tab}, socket) do
    socket
    |> patch(tab_active: tab)
  end

  @impl true
  defdelegate handle_event(name, params, socket), to: TodoplaceWeb.JobLive.Shared

  def handle_info({:update, %{job: job}}, socket) do
    socket
    |> assign(:job, job)
    |> put_flash(:success, "Job updated successfully")
    |> noreply()
  end

  @impl true
  def handle_info(
        {:proposal_message_composed, message_changeset, recipients},
        %{assigns: %{current_user: current_user, job: job}} = socket
      ) do
    socket
    |> upsert_booking_proposal(true)
    |> Ecto.Multi.merge(fn _ ->
      Messages.add_message_to_job(message_changeset, job, recipients, current_user)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{client_message: message, client_message_recipients: _}} ->
        job =
          job
          |> Repo.preload([:client, :job_status, package: [:contract, :questionnaire_template]],
            force: true
          )

        ClientNotifier.deliver_booking_proposal(message, recipients)

        socket
        |> assign_proposal()
        |> assign(job: job, package: job.package)
        |> TodoplaceWeb.ConfirmationComponent.open(%{
          title: "Email sent",
          subtitle: "Yay! Your email has been successfully sent"
        })
        |> noreply()

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to create booking proposal. Please try again.")
        |> noreply()
    end
  end

  def handle_info({:confirm_event, "edit_package"}, %{assigns: assigns} = socket) do
    socket
    |> open_modal(
      TodoplaceWeb.PackageLive.WizardComponent,
      assigns |> Map.take([:current_user, :job, :package, :currency])
    )
    |> assign_disabled_copy_link()
    |> noreply()
  end

  @impl true
  def handle_info({:stripe_status, status}, socket) do
    socket
    |> assign(stripe_status: status)
    |> assign_disabled_copy_link()
    |> noreply()
  end

  @impl true
  def handle_info({:contract_saved, contract}, %{assigns: %{package: package}} = socket) do
    socket
    |> assign(package: %{package | contract: contract})
    |> put_flash(:success, "New contract added successfully")
    |> close_modal()
    |> assign_disabled_copy_link()
    |> noreply()
  end

  @impl true
  def handle_info({:update_emails_count, %{job_id: job_id}}, socket) do
    socket
    |> assign_emails_count(job_id)
    |> noreply()
  end

  @impl true
  defdelegate handle_info(message, socket), to: JobLive.Shared

  def next_reminder_on(nil), do: nil

  def next_reminder_on(%{sent_to_client: false}), do: nil

  defdelegate next_reminder_on(proposal), to: Todoplace.ProposalReminder

  defp upsert_booking_proposal(
         %{
           assigns: %{
             proposal: proposal,
             job: job,
             package: package,
             include_questionnaire: include_questionnaire
           }
         },
         sent_to_client \\ false
       ) do
    questionnaire_id =
      if include_questionnaire, do: job |> Questionnaire.for_job() |> Repo.one() |> Map.get(:id)

    changeset =
      BookingProposal.changeset(%{
        job_id: job.id,
        questionnaire_id: questionnaire_id,
        sent_to_client: sent_to_client
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :proposal,
      if(proposal, do: Ecto.Changeset.put_change(changeset, :id, proposal.id), else: changeset),
      on_conflict: {:replace, [:questionnaire_id, :sent_to_client]},
      conflict_target: :id
    )
    |> Ecto.Multi.merge(fn _ ->
      Contracts.maybe_add_default_contract_to_package_multi(package)
    end)
  end

  defp assign_stripe_status(%{assigns: %{current_user: current_user}} = socket) do
    socket |> assign(stripe_status: Payments.status(current_user))
  end

  defp open_questionnaire_modal(socket, current_user, questionnaire) do
    socket
    |> TodoplaceWeb.QuestionnaireFormComponent.open(%{
      state: :edit_lead,
      current_user: current_user,
      questionnaire: questionnaire
    })
  end

  defp maybe_insert_questionnaire(template, current_user, %{id: package_id} = package) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:questionnaire_insert, fn _ ->
      Questionnaire.clean_questionnaire_for_changeset(
        template,
        current_user.organization_id,
        package_id
      )
      |> Questionnaire.changeset()
    end)
    |> Ecto.Multi.update(:package_update, fn %{questionnaire_insert: questionnaire} ->
      package
      |> Todoplace.Package.changeset(
        %{questionnaire_template_id: questionnaire.id},
        step: :details
      )
    end)
    |> Repo.transaction()
  end

  defp patch(%{assigns: %{job: job}} = socket, opts) do
    socket
    |> push_patch(to: ~p"/leads/#{job.id}?#{opts}")
    |> noreply()
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

  defp build_notes_changeset(%{assigns: %{job: job}}, params) do
    Job.notes_changeset(job, params)
  end

  defp actions_event(socket, action, proposal) do
    if action == "view" do
      socket
      |> push_event("ViewClientLink", %{"url" => BookingProposal.url(proposal.id)})
    else
      socket
      |> push_event("CopyToClipboard", %{"url" => BookingProposal.url(proposal.id)})
    end
  end

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
end
