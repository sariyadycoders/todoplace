defmodule TodoplaceWeb.Live.Admin.AutomatedEmails do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: :admin]
  import TodoplaceWeb.LiveHelpers
  import TodoplaceWeb.EmailAutomationLive.Shared, only: [is_state_manually_trigger: 1]

  alias Todoplace.{EmailAutomationSchedules, Repo, EmailAutomations, Shoots}

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign_defaults()
    |> assign_collapsed_sections()
    |> ok()
  end

  # join: category in assoc(pipeline, :email_automation_category),
  @impl true
  def render(assigns) do
    ~H"""
      <header class="p-8 bg-gray-100">
        <h1 class="text-4xl font-bold">Manage Automated Emails</h1>
      </header>

      <div class="p-12 flex flex-row space-between items-center">
        <%= if Enum.any?(@organization_emails) do %>
          <div class="flex flex-col">
            <div class="flex items-center flex-wrap">
              <h1 class="text-4xl font-bold">Ready to Send Emails</h1>
            </div>
            <div class="max-w-4xl mt-2 text-base-250">
              <p>Unlock Seamless Communication: Your Emails, Perfected and Ready for Dispatch! 🚀</p>
            </div>
          </div>
          <div class="flex ml-auto">
            <button testid="send-global" class="h-8 flex items-center px-2 py-1 btn-tertiary text-black font-bold hover:border-blue-planning-300 mr-2 whitespace-nowrap" phx-click="confirm-global-send">
              Send Emails Globally
            </button>
          </div>
        <% else %>
          <div class="flex flex-col">
            <div class="flex items-center flex-wrap">
              <h1 class="text-4xl font-bold">No Emails are ready to dispatch</h1>
            </div>
            <div class="max-w-4xl mt-2 text-base-250">
              <p>Make sure you have some in pipeline before coming here!</p>
            </div>
          </div>
        <% end %>
      </div>
      <.pipeline_section organization_emails={@organization_emails} collapsed_sections={@collapsed_sections}/>
    """
  end

  defp pipeline_section(assigns) do
    ~H"""
      <div class="flex flex-col px-32">
        <%= Enum.map(@organization_emails, fn organization -> %>
          <div testid="pipeline-section" class="mb-3 md:mr-4 border border-base-200 rounded-lg">
            <div class="flex bg-base-200 pl-2 pr-7 py-3 items-center cursor-pointer" phx-click="toggle-section" phx-value-organization_id={organization.id}>
              <div class="flex flex-col">
                <div class=" flex flex-row items-center">
                  <div class="flex-row w-8 h-8 rounded-full bg-white flex items-center justify-center">
                      <.icon name="play-icon" class="w-5 h-5 text-blue-planning-300" />
                  </div>
                  <span class="flex items-center text-blue-planning-300 text-xl ml-2">
                    <span class="font-bold">Organization name:</span> &nbsp; <%= organization.name %>
                    <span class="text-base-300 ml-2 rounded-md bg-white px-2 text-sm font-bold whitespace-nowrap"><%= organization.emails |> Enum.count() %></span>
                  </span>
                </div>
                <p class="text:xs text-base-250 lg:text-base ml-10">
                  Open the dropdown to see and send the ready-emails for this organization
                  <br />
                  <span class="font-bold">Org id:</span> &nbsp; <%= organization.id %>
                  <br />
                  <span class="font-bold">Photographer email:</span> &nbsp; <%= organization.photographer_email %>
                </p>
              </div>

              <div class="flex items-center ml-auto">
                <%= if Enum.any?(organization.emails) do %>
                  <button class="h-8 flex items-center px-2 py-1 bg-blue-planning-300 text-white font-bold mr-2 whitespace-nowrap rounded-md hover:opacity-75" phx-click="confirm-send-all-emails" phx-value-organization_id={organization.id}>
                    Send All
                  </button>
                  <button class="h-8 flex items-center px-2 py-1 bg-blue-planning-300 text-white font-bold mr-2 whitespace-nowrap rounded-md hover:opacity-75" phx-click="confirm-stop-all-emails" phx-value-organization_id={organization.id}>
                    Stopped All
                  </button>
                <% end %>
                <%= if Enum.member?(@collapsed_sections, organization.id) do %>
                  <.icon name="down" class="w-5 h-5 stroke-2 text-blue-planning-300" />
                <% else %>
                  <.icon name="up" class="w-5 h-5 stroke-2 text-blue-planning-300" />
                <% end %>
              </div>
            </div>

            <div class="flex flex-col">
              <% emails = organization.emails %>
              <%= if !Enum.member?(@collapsed_sections, organization.id) do %>
                <%= Enum.map(emails, fn email -> %>
                  <div class="flex flex-col md:flex-row pl-2 pr-7 md:items-center justify-between p-6">
                    <div class="flex flex-col ml-8 h-max items-center">
                      <div class="flex gap-2 flex-col">
                        <div class="flex flex-row items-center">
                          <.icon name="play-icon" class="w-4 h-4 text-blue-planning-300" />
                          <div class="flex gap-4 ml-2">
                            <% {state_name, email_name} = generate_email_name(email) %>
                            <p><span class="font-bold"><%= state_name %></span> <%= email_name %></p>
                          </div>
                        </div>
                        <div class="text-base-250">
                          The email you're seeing above is ready to be sent
                          <p><span class="font-bold">Email id:</span> <%= email.id %></p>
                          <p><span class="font-bold">Job id:</span> <%= email.job_id %></p>
                          <p><span class="font-bold">Send Date:</span> <%= get_marked_date(email) %></p>
                        </div>
                      </div>
                    </div>
                    <div class="flex justify-end mr-2">
                      <button class="h-8 flex items-center px-2 py-1 btn-tertiary text-black font-bold hover:border-blue-planning-300 mr-2 whitespace-nowrap" phx-click="confirm-send-now" phx-value-email_id={email.id}}>
                        Send now
                      </button>
                      <button class="h-8 flex items-center px-2 py-1 btn-tertiary text-black font-bold hover:border-blue-planning-300 mr-2 whitespace-nowrap" phx-click="confirm-stop-now" phx-value-email_id={email.id}}>
                        Stop now
                      </button>
                    </div>
                  </div>
                  <hr class="md:ml-8 ml-6">
                <% end) %>
              <% end %>
            </div>
          </div>
        <% end) %>
      </div>
    """
  end

  @impl true
  def handle_event(
        "toggle-section",
        %{"organization_id" => organization_id},
        %{assigns: %{collapsed_sections: collapsed_sections}} = socket
      ) do
    organization_id = to_integer(organization_id)

    collapsed_sections =
      if Enum.member?(collapsed_sections, organization_id) do
        Enum.filter(collapsed_sections, &(&1 != organization_id))
      else
        collapsed_sections ++ [organization_id]
      end

    socket
    |> assign(:collapsed_sections, collapsed_sections)
    |> noreply()
  end

  @impl true
  def handle_event(
        "confirm-global-send",
        _,
        socket
      ) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Are you sure you want to send emails globally?",
      subtitle:
        "Send your emails globally will send all the emails of all the organizations that are ready to send",
      confirm_event: "send-global-emails",
      confirm_label: "Yes, send them",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "confirm-send-all-emails",
        %{"organization_id" => organization_id},
        socket
      ) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Are you sure you want to send all emails of this organization?",
      subtitle: "This will send all of your ready-to-send emails for this specific organization",
      confirm_event: "send-all-emails-#{organization_id}",
      confirm_label: "Yes, send them",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "confirm-stop-all-emails",
        %{"organization_id" => organization_id},
        socket
      ) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Are you sure you want to stop all emails of this organization?",
      subtitle: "This will stop all of your ready-to-send emails for this specific organization",
      confirm_event: "stop-all-emails-#{organization_id}",
      confirm_label: "Yes, stop them",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "confirm-send-now",
        %{"email_id" => email_id},
        socket
      ) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Are you sure your want to send this email?",
      subtitle: "This will send only this specific selected email for this organization",
      confirm_event: "send-now-#{email_id}",
      confirm_label: "Yes, send it",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "confirm-stop-now",
        %{"email_id" => email_id},
        socket
      ) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Are you sure your want to stop this email?",
      subtitle: "This will stop only this specific selected email for this organization",
      confirm_event: "stop-now-#{email_id}",
      confirm_label: "Yes, stop it",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "send-global-emails"},
        socket
      ) do
    EmailAutomationSchedules.send_all_global_emails()
    |> case do
      {:ok, _} ->
        socket
        |> put_flash(:success, "Emails have been sent globally!")

      _ ->
        socket
        |> put_flash(:error, "Some error occurred on the way!")
    end
    |> close_modal()
    |> assign_defaults()
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "send-all-emails-" <> organization_id},
        socket
      ) do
    organization_id
    |> to_integer()
    |> EmailAutomationSchedules.send_all_emails_of_organization()
    |> case do
      {:ok, _} ->
        socket
        |> put_flash(:success, "All emails have been sent for the organization!")

      _ ->
        socket
        |> put_flash(:error, "Some error occurred on the way!")
    end
    |> close_modal()
    |> assign_defaults()
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "stop-all-emails-" <> organization_id},
        socket
      ) do
    organization_id
    |> to_integer()
    |> EmailAutomationSchedules.stop_all_emails_of_organization(:globally_stopped)
    |> case do
      {:ok, _} ->
        socket
        |> put_flash(:success, "All emails have been stop for the organization!")

      _ ->
        socket
        |> put_flash(:error, "Some error occurred on the way!")
    end
    |> close_modal()
    |> assign_defaults()
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "send-now-" <> email_id},
        socket
      ) do
    email_id
    |> to_integer()
    |> EmailAutomationSchedules.send_email_sechedule()
    |> case do
      {:ok, _} ->
        socket
        |> put_flash(:success, "Email Sent Successfully")

      _ ->
        socket
        |> put_flash(:error, "Error in Sending Email")
    end
    |> close_modal()
    |> assign_defaults()
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "stop-now-" <> email_id},
        socket
      ) do
    email_id
    |> to_integer()
    |> EmailAutomationSchedules.stop_email_sechedule(:globally_stopped)
    |> case do
      {:ok, _} ->
        socket
        |> put_flash(:success, "Email Stop Successfully")

      _ ->
        socket
        |> put_flash(:error, "Error in Stopping Email")
    end
    |> close_modal()
    |> assign_defaults()
    |> noreply()
  end

  defp assign_defaults(socket) do
    organization_emails = EmailAutomationSchedules.get_all_emails_for_approval()

    socket
    |> assign(organization_emails: organization_emails)
  end

  defp assign_collapsed_sections(%{assigns: %{organization_emails: organization_emails}} = socket) do
    collapsed_sections = organization_emails |> Enum.map(fn x -> x.id end)

    socket
    |> assign(:collapsed_sections, collapsed_sections)
  end

  defp get_marked_date(email) do
    email_state = get_state_from_email(email)
    email_category = get_category_from_email(email)
    category_type = if email.shoot_id, do: :shoot, else: email_category

    %{sign: sign} = EmailAutomations.explode_hours(email.total_hours)

    cond do
      email_state in ["before_shoot", "shoot_thanks"] ->
        email
        |> Map.get(:shoot, %{})
        |> Map.get(:starts_at)
        |> shift_time(sign, email.total_hours)

      email_state == "post_shoot" ->
        email.job_id
        |> Shoots.get_latest_shoot()
        |> case do
          nil -> nil
          shoot -> Map.get(shoot, :starts_at)
        end
        |> shift_time(sign, email.total_hours)

      is_state_manually_trigger(email_state) ->
        pipeline = EmailAutomations.get_pipeline_by_state(email_state)

        _last_completed_email =
          EmailAutomationSchedules.get_last_completed_email(
            category_type,
            email.gallery_id,
            email.shoot_id,
            email.job_id,
            pipeline.id,
            email_state,
            TodoplaceWeb.EmailAutomationLive.Shared
          )
          |> case do
            nil -> nil
            last_email -> Map.get(last_email, :reminded_at)
          end
          |> shift_time(sign, email.total_hours)

      email_state == "gallery_expiration_soon" ->
        _gallery_expiration_date =
          Repo.preload(email, [:gallery])
          |> Map.get(:gallery)
          |> Map.get(:expired_at)
          |> shift_time(sign, email.total_hours)

      true ->
        email.updated_at |> Calendar.strftime("%a, %B %d %Y %I:%M:%S %p")
    end
  end

  defp shift_time(nil, _sign, _hours), do: nil

  defp shift_time(time, sign, hours),
    do:
      if(sign == "+", do: Timex.shift(time, hours: hours), else: Timex.shift(time, hours: hours))
      |> Calendar.strftime("%a, %B %d %Y %I:%M:%S %p")

  defp generate_email_name(email) do
    email_state = get_state_from_email(email)

    %{calendar: calendar, count: count, sign: sign} =
      EmailAutomations.get_email_meta(email.total_hours, TodoplaceWeb.Helpers)

    {"[#{convert_to_readable(email_state)}]",
     "#{email.name} - #{count} #{calendar} #{sign} email"}
  end

  defp convert_to_readable(input) do
    input
    |> String.split("_")
    |> Enum.map_join(" ", &capitalize_word/1)
  end

  defp capitalize_word(word), do: String.capitalize(word)

  defp get_state_from_email(email) do
    email
    |> preload_email()
    |> Map.get(:email_automation_pipeline)
    |> Map.get(:state)
    |> Atom.to_string()
  end

  defp get_category_from_email(email) do
    email
    |> preload_email()
    |> Map.get(:email_automation_pipeline)
    |> Map.get(:email_automation_category)
    |> Map.get(:category_type)
  end

  defp preload_email(email),
    do:
      email
      |> Repo.preload([:shoot, email_automation_pipeline: [:email_automation_category]])
end
