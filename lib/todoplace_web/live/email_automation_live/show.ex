defmodule TodoplaceWeb.Live.EmailAutomations.Show do
  @moduledoc false
  use TodoplaceWeb, :live_view
  import Todoplace.Onboardings, only: [save_intro_state: 3]

  import TodoplaceWeb.JobLive.Shared,
    only: [
      assign_job: 2,
      validate_payment_schedule: 1,
      assign_disabled_copy_link: 1,
      tabs_list: 1
    ]

  import TodoplaceWeb.EmailAutomationLive.Shared,
    only: [
      assign_collapsed_sections: 1,
      is_state_manually_trigger: 1,
      sort_emails: 2,
      get_pipline: 1,
      get_email_schedule_text: 6,
      get_email_name: 4,
      get_preceding_email: 2,
      fetch_date_for_state_maybe_manual: 6
    ]

  import TodoplaceWeb.LiveHelpers
  import Ecto.Query

  alias Todoplace.{
    Marketing,
    Galleries,
    EmailAutomations,
    EmailAutomationSchedules,
    Repo,
    Payments
  }

  @impl true
  def mount(
        %{"live_action" => live_action, "id" => id} = _params,
        _session,
        %{assigns: %{current_user: _current_user}} = socket
      ) do
    socket
    |> assign_stripe_status()
    |> assign(:main_class, "bg-gray-100")
    |> assign(:live_action, String.to_atom(live_action))
    |> assign(:request_from, :jobs)
    |> assign(:tab_active, "automations")
    |> assign_job(to_integer(id))
    |> assign(:job_id, to_integer(id))
    |> assign_email_schedules()
    |> assign_collapsed_sections()
    |> then(fn %{assigns: assigns} = socket ->
      job = Map.get(assigns, :job)

      if job do
        payment_schedules = job |> Repo.preload(:payment_schedules) |> Map.get(:payment_schedules)

        socket
        |> assign(payment_schedules: payment_schedules)
        |> assign(:type, %{singular: "job", plural: "jobs"})
        |> assign(:tabs, tabs_list(if job.job_status.is_lead, do: nil, else: :jobs))
        |> validate_payment_schedule()
        |> assign_disabled_copy_link()
      else
        socket
        |> assign(:type, %{singular: "lead", plural: "leads"})
        |> assign(:tabs, tabs_list(nil))
      end
    end)
    |> assign_job_types()
    |> ok()
  end

  @impl true
  def handle_event(
        "intro-close-automations",
        _,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    socket
    |> assign(current_user: save_intro_state(current_user, "intro_automations", :dismissed))
    |> noreply()
  end

  @impl true
  def handle_event(
        "toggle-section",
        %{"section_id" => section_id},
        %{assigns: %{collapsed_sections: collapsed_sections}} = socket
      ) do
    collapsed_sections =
      if Enum.member?(collapsed_sections, section_id),
        do: Enum.filter(collapsed_sections, &(&1 != section_id)),
        else: collapsed_sections ++ [section_id]

    socket
    |> assign(:collapsed_sections, collapsed_sections)
    |> noreply()
  end

  @impl true
  def handle_event("confirm-stop-email", %{"email_id" => email_id}, socket) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      modal_name: :automation_email_modal,
      title: "Are you sure you want to stop this email?",
      subtitle:
        "<strong>Stop</strong> this email and your client will get the next email in the sequence. To stop the full automation sequence from sending, you will need to <strong>Stop</strong> each email individually.",
      confirm_event: "stop-email-schedule-" <> email_id,
      confirm_label: "Yes, stop email",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "confirm-send-email",
        %{"email_id" => email_id, "pipeline_id" => pipeline_id},
        socket
      ) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Are you sure you want to send this email?",
      subtitle:
        "Send your email now will complete this email and the next email will go out at the specified time that you set up in global automation settings",
      confirm_event: "send-email-now-" <> email_id <> "-" <> pipeline_id,
      confirm_label: "Yes, send email",
      modal_name: :automation_email_modal,
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "edit-email",
        %{"email_id" => id, "pipeline_id" => pipeline_id, "index" => index},
        %{
          assigns: %{
            current_user: current_user,
            automation_job_type: automation_job_type,
            job_types: job_types,
            job: job
          }
        } = socket
      ) do
    selected_job_type =
      job_types |> Enum.filter(fn x -> x.job_type == automation_job_type end) |> List.first()

    socket
    |> open_modal(TodoplaceWeb.EmailAutomationLive.EditEmailScheduleComponent, %{
      current_user: current_user,
      job: job,
      job_type: selected_job_type.jobtype,
      job_types: job_types,
      pipeline: get_pipline(to_integer(pipeline_id)),
      email: EmailAutomationSchedules.get_schedule_by_id(to_integer(id)),
      index: to_integer(index)
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "email-preview",
        %{"email-preview-id" => id, "is-preview" => is_preview?},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    is_preview? = String.to_atom(is_preview?)
    email_schedule = EmailAutomationSchedules.get_schedule_by_id(id)

    email =
      if is_preview? do
        email_schedule
      else
        EmailAutomationSchedules.get_schedule_history_by_id(id)
      end
      |> Repo.preload(email_automation_pipeline: :email_automation_category)

    email_type = email.type
    schemas = automation_schemas(email, email_type)

    %{body_template: body_html} =
      EmailAutomations.resolve_variables(email, schemas, TodoplaceWeb.Helpers)

    template_preview = Marketing.template_preview(current_user, body_html)

    socket
    |> TodoplaceWeb.EmailAutomationLive.TemplatePreviewComponent.open(%{
      template_preview: template_preview
    })
    |> noreply()
  end

  @impl true
  def handle_event("change-tab", %{"tab" => tab}, socket) do
    socket
    |> patch(tab_active: tab)
  end

  defp patch(%{assigns: %{job: job}} = socket, opts) do
    if job.job_status.is_lead do
      socket
      |> push_redirect(to: ~p"/leads/#{job.id}?#{opts}")
    else
      socket
      |> push_redirect(to: ~p"/jobs/#{job.id}?#{opts}")
    end
    |> noreply()
  end

  @impl true
  defdelegate handle_event(name, params, socket), to: TodoplaceWeb.JobLive.Shared

  @impl true
  def handle_info({:confirm_event, "send-email-now-" <> param}, socket) do
    [id, _pipeline_id] = String.split(param, "-")
    id = to_integer(id)

    EmailAutomationSchedules.send_email_sechedule(id)
    |> case do
      {:ok, _} ->
        socket
        |> put_flash(:success, "Email Sent Successfully")

      _ ->
        socket
        |> put_flash(:error, "Error in Sending Email")
    end
    |> close_modal()
    |> assign_email_schedules()
    |> noreply()
  end

  @impl true
  def handle_info({:confirm_event, "stop-email-schedule-" <> id}, socket) do
    stopped_email =
      id
      |> to_integer()
      |> EmailAutomationSchedules.stop_email_sechedule(:photographer_stopped)

    case stopped_email do
      {:ok, _} -> socket |> put_flash(:success, "Email Stopped Successfully")
      _ -> socket |> put_flash(:error, "Error in Updating Email")
    end
    |> close_modal()
    |> assign_email_schedules()
    |> noreply()
  end

  @impl true
  def handle_info({:update_automation, %{message: message}}, socket) do
    socket
    |> assign_email_schedules()
    |> put_flash(:success, message)
    |> noreply()
  end

  @impl true
  defdelegate handle_info(message, socket), to: TodoplaceWeb.EmailAutomationLive.Shared

  defp pipeline_section(assigns) do
    ~H"""

    <%= if Enum.member?(@collapsed_sections, @subcategory) do %>
      <% sorted_emails = sort_emails(@pipeline.emails, @pipeline.state) %>
      <div testid="pipeline-section" class="mb-3 md:mr-4 border border-base-200 rounded-lg">
        <% next_email = get_next_email_schdule_date(@category_type, sorted_emails, @pipeline.id, @pipeline.state, @subcategory_slug) %>
        <% email_is_completed? = next_email.is_completed %>
        <div class={classes("flex justify-between p-2", %{"opacity-60" => email_is_completed?})}>
            <% stopped_email_text = EmailAutomationSchedules.get_stopped_emails_text(@job_id, @pipeline.state, TodoplaceWeb.Helpers) %>
            <%= if stopped_email_text do %>
              <span class="pl-1 text-red-sales-300 font-bold"> <%= stopped_email_text %> </span>
            <% else %>
              <span class="pl-1 text-blue-planning-300 font-bold"> <%= next_email.text %> </span>
            <% end %>
          <%= if not is_nil(next_email.email_preview_id) do %>
            <span class="text-blue-planning-300 pr-4 underline hover:cursor-pointer" phx-click="email-preview" phx-value-email-preview-id={next_email.email_preview_id} phx-value-is-preview={true} >Preview</span>
          <% end %>
        </div>

        <div class={classes("flex bg-base-200 pl-2 pr-7 py-3 items-center cursor-pointer", %{"opacity-60" => email_is_completed?})} phx-click="toggle-section" phx-value-section_id={"pipeline-#{@pipeline.id}-#{@subcategory}"}>

          <div class="flex flex-col">
            <div class=" flex flex-row items-center">
              <div class="flex-row w-8 h-8 rounded-full bg-white flex items-center justify-center">
                <%= if is_state_manually_trigger(@pipeline.state) do %>
                  <.icon name="paper-airplane" class="w-5 h-5 text-blue-planning-300" />
                <% else %>
                  <.icon name="play-icon" class="w-5 h-5 text-blue-planning-300" />
                <% end %>
              </div>
              <span class="flex items-center text-blue-planning-300 text-xl font-bold ml-2">
                <%= @pipeline.name %>
                <span class="text-base-300 ml-2 rounded-md bg-white px-2 text-sm font-bold whitespace-nowrap"><%= Enum.count(sorted_emails) %> <%=ngettext("email", "emails", Enum.count(sorted_emails)) %></span>
                <%= if is_state_manually_trigger(@pipeline.state) do %>
                  <span class="text-base-300 ml-2 rounded-md bg-white px-2 text-sm font-bold whitespace-nowrap">Manual Trigger</span>
                <% end %>
              </span>
            </div>
            <p class="text:xs text-base-250 lg:text-base ml-10">
              <%= @pipeline.description %>
            </p>
          </div>

          <div class="ml-auto">
            <%= if !Enum.member?(@collapsed_sections, "pipeline-#{@pipeline.id}-#{@subcategory}") do %>
                <.icon name="down" class="w-5 h-5 stroke-2 text-blue-planning-300" />
              <% else %>
                <.icon name="up" class="w-5 h-5 stroke-2 text-blue-planning-300" />
              <% end %>
            </div>
        </div>

        <%= if Enum.member?(@collapsed_sections, "pipeline-#{@pipeline.id}-#{@subcategory}") do %>
          <%= Enum.with_index(sorted_emails, fn email, index -> %>
              <% last_index = Enum.count(sorted_emails) - 1 %>
              <% is_email_disable = disable_send_stop_email(email, sorted_emails, @pipeline.state, index)%>
            <div class="flex flex-col md:flex-row pl-2 pr-7 md:items-center justify-between">
              <div class={classes("flex flex-row ml-2 h-max", %{"opacity-60" => email_is_completed?})}>
                <div class={"h-auto pt-3 md:relative #{index != last_index && "md:before:absolute md:before:border md:before:h-full md:before:border-base-200 md:before:left-1/2 md:before:z-10 md:before:z-[-1]"}"}>
                  <div class="flex w-8 h-8 rounded-full items-center justify-center bg-base-200 z-40">
                    <%= cond do %>
                      <% not is_nil(email.reminded_at) -> %> <.icon name="tick" class="w-5 h-5 text-blue-planning-300" />
                      <% not is_nil(email.stopped_at) -> %> <.icon name="stop" class="w-5 h-5 text-red-sales-300" />
                      <% is_state_manually_trigger(@pipeline.state) and index == 0 -> %> <.icon name="paper-airplane" class="w-5 h-5 text-blue-planning-300" />
                      <% true -> %>  <.icon name="envelope" class="w-5 h-5 text-blue-planning-300" />
                    <% end %>
                  </div>
                </div>
                <span class={classes("text-sm font-bold ml-4 py-3", %{"text-blue-planning-300" => not is_nil(email.reminded_at), "text-red-sales-300" => not is_nil(email.stopped_at)})}>
                  <%= if not is_nil(email.reminded_at) do %>
                    Completed <%= get_date(email.reminded_at) %>
                  <% end %>
                  <%= if not is_nil(email.stopped_at) do %>
                    Stopped <%= get_date(email.stopped_at) %> | Reason: <%= stop_reason_text(email.stopped_reason) %>
                  <% end %>

                  <p class="text-black text-xl">
                    <%= get_email_name(email, @type, index, @pipeline.state) %>
                    <%= if not is_nil(email.stopped_at) do %>
                      <span testid={"#{@pipeline.state}-stop_text-#{index}"} class="ml-2 rounded-md bg-red-sales-100 text-red-sales-300 px-2 pb-1 text-sm font-bold whitespace-nowrap">Stopped</span>
                    <% end %>
                  </p>
                  <div class="flex items-center bg-white">
                    <div class="w-4 h-4 mr-2">
                      <.icon name="play-icon" class="w-4 h-4 text-blue-planning-300" />
                    </div>
                    <p class="font-normal text-base-250 text-sm">
                      <%= get_email_schedule_text(email.total_hours, @pipeline.state, sorted_emails, index, @type, @current_user.organization_id) %>
                    </p>
                  </div>
                </span>
              </div>

              <div class="flex justify-end mr-2">
                <%= if not (is_state_manually_trigger(@pipeline.state) and index == 0) do %>
                  <.icon_button_simple testid={"#{@pipeline.state}-stop_button-#{index}"} class={classes("flex flex-row items-center justify-center w-8 h-8 bg-base-200 mr-2 rounded-xl", %{"opacity-30 hover:cursor-not-allowed" => is_email_disable})} disabled={is_email_disable} phx-click="confirm-stop-email" phx-value-email_id={email.id} icon_class="flex flex-col items-center justify-center w-5 h-5" color="red-sales-300" icon="stop"></.icon_button_simple>
                <% end %>
                <% allow_cursor? = !is_nil(email.stopped_at) || !is_nil(email.reminded_at) %>
                <button testid="email_send_OR_start_sequence" disabled={is_email_disable} class={classes("h-8 flex items-center px-2 py-1 btn-tertiary text-black font-bold  hover:border-blue-planning-300 mr-2 whitespace-nowrap", %{"opacity-30 hover:cursor-not-allowed" => allow_cursor? || disable_pipeline?(sorted_emails, @pipeline.state, index), "hidden" => @subcategory_slug == "payment_reminder_emails"})} phx-click="confirm-send-email" phx-value-email_id={email.id} phx-value-pipeline_id={@pipeline.id}>
                  <%= if is_state_manually_trigger(@pipeline.state) and index == 0 do %>
                      Start Sequence
                    <% else %>
                      Send now
                  <% end %>
                </button>
                <% icon_btn_class = "h-8 flex items-center px-2 py-1 btn-tertiary bg-blue-planning-300 text-white hover:bg-blue-planning-300/75 whitespace-nowrap" %>
                <%= if allow_cursor? do %>
                    <.icon_button_simple  class={icon_btn_class} phx-click="email-preview" phx-value-email-preview-id={email.id} phx-value-is-preview="false" icon_class="inline-block w-4 h-4 mr-3" color="white" icon="eye">View email</.icon_button_simple>
                  <% else %>
                    <.icon_button_simple  class={icon_btn_class} phx-click="edit-email" phx-value-index={index} phx-value-email_id={email.id} phx-value-pipeline_id={@pipeline.id} icon_class="inline-block w-4 h-4 mr-3" color="white" icon="pencil">Edit email</.icon_button_simple>
                <% end %>
              </div>
            </div>
          <% end) %>
      <% end %>
      </div>
    <% end %>
    """
  end

  defp automation_schemas(schedule, type) when type in [:lead, :job, :shoot] do
    schedule = Repo.preload(schedule, [:job])
    payment_schedule = EmailAutomations.get_latest_payment_schedule(schedule.job)
    {schedule.job, payment_schedule}
  end

  defp automation_schemas(schedule, type) when type in [:gallery, :order] do
    schedule = Repo.preload(schedule, [:gallery])

    gallery =
      schedule.gallery |> Galleries.set_gallery_hash() |> Repo.preload([:albums, job: :client])

    EmailAutomations.schemas(gallery)
  end

  defp automation_schemas(_schedule, _type), do: {nil}

  defp assign_job_types(
         %{assigns: %{current_user: current_user, automation_job_type: automation_job_type}} =
           socket
       ) do
    current_user =
      current_user
      |> Repo.preload([organization: [organization_job_types: :jobtype]], force: true)

    job_types =
      current_user.organization.organization_job_types
      |> Enum.sort_by(& &1.jobtype.position)

    selected_job_type =
      job_types |> Enum.filter(fn x -> x.job_type == automation_job_type end) |> List.first()

    socket
    |> assign(:current_user, current_user)
    |> assign(:job_types, job_types)
    |> assign(:selected_job_type, selected_job_type)
  end

  defp assign_email_schedules(%{assigns: %{job_id: job_id, job: job}} = socket) do
    galleries = Galleries.get_galleries_by_job_id(job_id) |> Enum.map(& &1.id)

    gallery_emails = EmailAutomationSchedules.get_email_schedules_by_ids(galleries, :gallery)
    jobs_emails = EmailAutomationSchedules.get_email_schedules_by_ids(job_id, :job)
    email_schedules = jobs_emails ++ gallery_emails

    socket
    |> assign(:automation_job_type, job.type)
    |> assign(email_schedules: email_schedules)
  end

  defp get_next_email_schdule_date(category_type, emails, pipeline_id, state, subcategory) do
    email = emails |> List.first()
    category_type = if email.shoot_id, do: :shoot, else: category_type

    email_schedule =
      EmailAutomationSchedules.query_get_email_schedule(
        category_type,
        email.gallery_id,
        email.shoot_id,
        email.job_id,
        pipeline_id
      )
      |> where([es], is_nil(es.reminded_at))
      |> where([es], is_nil(es.stopped_at))
      |> Repo.all()
      |> sort_emails(state)
      |> List.first()

    last_completed_email =
      EmailAutomationSchedules.get_last_completed_email(
        category_type,
        email.gallery_id,
        email.shoot_id,
        email.job_id,
        pipeline_id,
        state,
        TodoplaceWeb.EmailAutomationLive.Shared
      )

    case {email_schedule, last_completed_email} do
      {nil, nil} ->
        %{
          text: "",
          date: "",
          email_preview_id: nil,
          is_completed: false
        }

      {nil, _} ->
        %{
          text: "Completed",
          date: last_completed_email.reminded_at |> Calendar.strftime("%m/%d/%Y"),
          email_preview_id: nil,
          is_completed: true
        }

      _ ->
        get_next_email_by(email_schedule, email, state, pipeline_id, subcategory)
    end
  end

  defp get_next_email_by(email_schedule, email, state, pipeline_id, subcategory) do
    %{sign: sign} = EmailAutomations.explode_hours(email_schedule.total_hours)
    job = EmailAutomations.get_job(email.job_id)

    gallery =
      if is_nil(email.gallery_id),
        do: nil,
        else: EmailAutomations.get_gallery(email.gallery_id)

    state = if is_atom(state), do: state, else: String.to_atom(state)
    date = get_conditional_date(state, email_schedule, pipeline_id, job, gallery)

    cond do
      not is_nil(date) ->
        %{
          text: "Next Email",
          date: next_schedule_format(date, sign, email_schedule.total_hours),
          email_preview_id: email_schedule.id,
          is_completed: false
        }

      subcategory == "payment_reminder_emails" ->
        %{
          text: "Transactional",
          date: "",
          email_preview_id: email_schedule.id,
          is_completed: false
        }

      true ->
        %{
          text: "Next Email",
          date: "",
          email_preview_id: email_schedule.id,
          is_completed: false
        }
    end
  end

  defp next_schedule_format(date, sign, hours) do
    if sign == "+" do
      DateTime.add(date, hours * 60 * 60)
    else
      DateTime.add(date, -1 * (hours * 60 * 60))
    end
    |> Calendar.strftime("%m/%d/%Y")
  end

  defp get_date(date) do
    {:ok, converted_date} = NaiveDateTime.from_iso8601(date)
    converted_date |> Calendar.strftime("%m/%d/%Y")
  end

  defp disable_send_stop_email(email, sorted_emails, state, index) do
    cond do
      not is_nil(email.stopped_at) -> true
      not is_nil(email.reminded_at) -> true
      true -> disable_pipeline?(sorted_emails, state, index)
    end
  end

  defp disable_pipeline?(_emails, _state, 0), do: false

  defp disable_pipeline?(emails, state, _index) do
    is_manual_trigger = is_state_manually_trigger(state)
    intial_email = get_preceding_email(emails, 1)
    if is_manual_trigger and is_nil(intial_email.reminded_at), do: true, else: false
  end

  defp get_conditional_date(state, _email, _pipeline_id, _job, _gallery)
       when state in [
              :order_arrived,
              :order_delayed,
              :order_shipped,
              :digitals_ready_download,
              :order_confirmation_digital_physical,
              :order_confirmation_digital,
              :order_confirmation_physical
            ],
       do: nil

  defp get_conditional_date(state, email, pipeline_id, job, gallery),
    do: fetch_date_for_state_maybe_manual(state, email, pipeline_id, job, gallery, nil)

  @status_texts %{
    "photographer_stopped" => "Stopped by Photographer",
    "proposal_accepted" => "Stopped since user accepted",
    "already_paid_full" => "Job has already been paid in full",
    "shoot_starts_at_passed" => "Shoot date has already passed",
    "gallery_already_shared_because_order_placed" => "Gallery has already been shared",
    "archived" => "Archived",
    "completed" => "Completed",
    "lead_converted_to_job" => "Lead has been converted to job",
    "globally_stopped" => "Globally Stopped"
  }
  def stop_reason_text(status), do: Map.get(@status_texts, status, "")

  defp assign_stripe_status(%{assigns: %{current_user: current_user}} = socket) do
    socket |> assign(stripe_status: Payments.status(current_user))
  end
end
