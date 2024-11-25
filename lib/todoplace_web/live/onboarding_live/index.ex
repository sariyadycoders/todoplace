defmodule TodoplaceWeb.OnboardingLive.Index do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: :onboarding]

  import TodoplaceWeb.GalleryLive.Shared, only: [steps: 1]
  import TodoplaceWeb.PackageLive.Shared, only: [current: 1]

  import TodoplaceWeb.OnboardingLive.Shared,
    only: [
      form_field: 1,
      save_final: 2,
      save_multi: 3,
      assign_changeset: 1,
      assign_changeset: 2,
      org_job_inputs: 1,
      most_interested_select: 0,
      country_info: 1,
      countries: 0,
      states_or_province: 1,
      field_for: 1
    ]

  require Logger

  alias Todoplace.{Subscriptions}

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign_step()
    |> assign(:stripe_loading, false)
    |> assign(
      :subscription_plan_metadata,
      Subscriptions.get_subscription_plan_metadata()
    )
    |> assign_changeset()
    |> ok()
  end

  @impl true
  def handle_event("previous", %{}, %{assigns: %{step: 2}} = socket), do: socket |> noreply()

  @impl true
  def handle_event("previous", %{}, %{assigns: %{step: step}} = socket) do
    socket |> assign_step(step - 1) |> assign_changeset() |> noreply()
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    IO.inspect(params, label: "params")

    socket |> assign_changeset(params) |> noreply()
  end

  @impl true
  def handle_event("validate", _params, socket) do
    socket |> assign_changeset() |> noreply()
  end

  @impl true
  def handle_event("save", %{"user" => params}, %{assigns: %{step: 3}} = socket) do
    save_final(socket, params)
  end

  @impl true
  def handle_event("save", %{"user" => %{"organization" => %{"id" => org_id}} = params}, socket) do
    {_, first_params} =
      get_and_update_in(params["organization"], fn data ->
        data = Map.delete(data, "organization_job_types")

        {data, data}
      end)

    final_params = %{
      "organization" => Map.get(params, "organization") |> Map.delete("name")
    }

    socket
    |> save(first_params)
    |> save_final(final_params)
  end

  @impl true
  def handle_event("go-dashboard", %{}, socket) do
    socket
    |> push_redirect(to: ~p"/home", replace: true)
    |> noreply()
  end

  @impl true
  def handle_event("trial-code", %{"code" => code}, socket) do
    supscription_plan_metadata = Subscriptions.get_subscription_plan_metadata(code)

    step_title =
      if socket.assigns.step === 4 do
        supscription_plan_metadata.onboarding_title
      else
        socket.assigns.step_title
      end

    socket
    |> assign(
      :subscription_plan_metadata,
      supscription_plan_metadata
    )
    |> assign(step_title: step_title)
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-blue-planning-300 fixed top-0 bottom-0 right-0 left-1/2 flex items-center justify-center">
      <image src="/images/tell_us.png" />
    </div>

    <div class="pl-10 pr-10 w-1/2 py-10 bg-gray-100">
      <div class={classes(["flex flex-col items-start justify-center"])}>
        <div class="flex items-end justify-between sm:items-center">
          <%!-- <.icon name="logo-shoot-higher" class="w-32 h-12 sm:h-20 sm:w-48" /> --%>

          <a title="previous" phx-click="previous" class="cursor-pointer sm:py-2">
            <ul class="flex items-center">
              <%= for step <- 1..2 do %>
                <li class={
                  classes(
                    "block w-5 h-5 sm:w-3 sm:h-3 rounded-full ml-3 sm:ml-2",
                    %{"bg-blue-planning-300" => step == @step, "bg-gray-200" => step != @step}
                  )
                }>
                </li>
              <% end %>
            </ul>
          </a>
        </div>
        <h1 class="text-3xl font-bold mt-7 sm:leading-tight sm:my-6">Tell us more about yourself</h1>
      </div>

      <.form
        :let={f}
        for={@changeset}
        phx-change="validate"
        phx-submit="save"
        id={"onboarding-step-#{@step}"}
      >
        <.step f={f} {assigns} />
        <div
          class="flex items-center justify-between mt-5 sm:justify-end sm:mt-9"
          phx-hook="HandleTrialCode"
          id="handle-trial-code"
          data-handle="retrieve"
        >
          <%= if @step > 2 do %>
            <button
              type="button"
              phx-click="previous"
              class="flex-grow px-6 sm:flex-grow-0 btn-secondary sm:px-8"
            >
              Back
            </button>
          <% else %>
          <% end %>
          <button
            type="submit"
            phx-disable-with="Saving"
            disabled={!@changeset.valid? || @stripe_loading}
            class="flex-grow px-6 ml-4 sm:flex-grow-0 btn-primary sm:px-8"
          >
            Start Trial
          </button>
        </div>
      </.form>
      <%= if @step == 2 do %>
        <.form :let={_} for={%{}} as={:sign_out} action={~p"/users/log_out"} method="delete">
          <div id="user-agent" phx-hook="UserAgent"></div>
          <%= submit("Logout", class: "flex-grow sm:flex-grow-0 underline mr-auto text-left") %>
        </.form>
      <% end %>
    </div>
    """
  end

  defp step(%{step: 2} = assigns) do
    assigns = assign(assigns, input_class: "p-4")

    ~H"""
    <.inputs_for :let={org} field={@f[:organization]}>
      <.form_field
        label="What’s the name of your business?"
        error={:name}
        prefix="Business name"
        f={org}
        mt={0}
      >
        <%= input(org, :name,
          phx_debounce: "500",
          placeholder: "Jack Nimble",
          class: @input_class
        ) %>
        <p class="italic text-sm text-gray-400 mt-2">
          We generate a URL for your Public Profile based on your business name. Here’s a preview: <%= url(
            ~p"/org/#{input_value(org, :slug)}"
          ) %>
        </p>
      </.form_field>

      <div class="hidden">
        <.inputs_for :let={jt} field={org[:organization_job_types]}>
          <% input_name = input_name(jt, :job_type) %>
          <%= if jt.data.job_type != "global" do %>
            <% checked = jt |> current() |> Map.get(:show_on_business?) %>
            <.job_type_option
              type="checkbox"
              name={input_name}
              form={jt}
              job_type={jt |> current() |> Map.get(:job_type)}
              checked={checked}
            />
          <% else %>
            <input
              class="hidden"
              type="checkbox"
              name={input_name}
              value={jt |> current() |> Map.get(:job_type)}
              checked={true}
            />
          <% end %>
          <%= hidden_input(jt, :type, value: jt |> current() |> Map.get(:job_type)) %>
        </.inputs_for>
      </div>
    </.inputs_for>
    <hr class="mt-6 border-base-200" />

    <.inputs_for :let={onboarding} field={@f[:onboarding]}>
      <hr class="mt-6 border-base-200" />

      <%= hidden_input(onboarding, :welcome_count, value: 0) %>

      <% info = country_info(input_value(onboarding, :country)) %>
      <div class={classes("grid gap-4", %{"sm:grid-cols-1" => Map.has_key?(info, :state_label)})}>
        <.form_field label="What’s your country?" error={:country} f={onboarding}>
          <%= select(onboarding, :country, [{"United States", :US}] ++ countries(),
            class: "select #{@input_class}"
          ) %>
        </.form_field>

        <.form_field label="Zipcode" error={:zipcode} f={onboarding}>
          <%= input(onboarding, :zipcode,
            phx_debounce: 500,
            placeholder: "e.g. 252550",
            class: @input_class
          ) %>
        </.form_field>
      </div>
    </.inputs_for>

    <.inputs_for :let={metadata} field={@f[:metadata]}>
      <div class="font-bold text-lg my-5">
        What brings you here today?
      </div>
      <div class="grid grid-cols-3 gap-3">
        <%= for field <- ["Work", "Personal", "School", "Non-profits"] do %>
          <% input_name = input_name(metadata, :purpose) %>
          <% checked = input_value(metadata, :purpose) == field %>
          <.custom_checkbox
            type="radio"
            name={input_name}
            form={metadata}
            job_type={field}
            checked={checked}
          />
        <% end %>
      </div>

      <% role_options = get_role_options(input_value(metadata, :purpose)) %>
      <div :if={Enum.any?(role_options)} class="font-bold text-lg my-5">
        What is your role?
      </div>
      <div :if={Enum.any?(role_options)} class="grid grid-cols-3 gap-3">
        <%= for field <- role_options do %>
          <% input_name = input_name(metadata, :role) %>
          <% checked = input_value(metadata, :role) == field %>
          <.custom_checkbox
            type="radio"
            name={input_name}
            form={metadata}
            job_type={field}
            checked={checked}
          />
        <% end %>
      </div>

      <div :if={input_value(metadata, :role) != "Freelancer"} class="font-bold text-lg my-5">
        How many peopple are on your team?
      </div>
      <div :if={input_value(metadata, :role) != "Freelancer"} class="grid grid-cols-3 gap-3">
        <%= for field <- ["Only me", "2 - 5", "6 - 10", "11 - 15", "16 - 25", "26 - 50", "51 - 100", "101 - 500"] do %>
          <% input_name = input_name(metadata, :team_size) %>
          <% checked = input_value(metadata, :team_size) == field %>
          <.custom_checkbox
            type="radio"
            name={input_name}
            form={metadata}
            job_type={field}
            checked={checked}
          />
        <% end %>
      </div>

      <div
        :if={
          input_value(metadata, :role) != "Freelancer" and input_value(metadata, :purpose) != "School"
        }
        class="font-bold text-lg my-5"
      >
        How many peopple work at your company?
      </div>
      <div
        :if={
          input_value(metadata, :role) != "Freelancer" and input_value(metadata, :purpose) != "School"
        }
        class="grid grid-cols-3 gap-3"
      >
        <%= for field <- ["1 - 19", "20 - 49", "50 - 99", "100 - 250", "251 - 500", "501 - 1500", "1500+"] do %>
          <% input_name = input_name(metadata, :company_size) %>
          <% checked = input_value(metadata, :company_size) == field %>
          <.custom_checkbox
            type="radio"
            name={input_name}
            form={metadata}
            job_type={field}
            checked={checked}
          />
        <% end %>
      </div>

      <div
        :if={input_value(metadata, :purpose) not in ["School", "Non-profits"]}
        class="font-bold text-lg my-5"
      >
        Select what would you like to manage first?
      </div>
      <div
        :if={input_value(metadata, :purpose) not in ["School", "Non-profits"]}
        class="grid grid-cols-3 gap-3"
      >
        <%= for field <- manage_options() do %>
          <% input_name = input_name(metadata, :first_manage) %>
          <% checked = input_value(metadata, :first_manage) == field %>
          <.custom_checkbox
            type="radio"
            name={input_name}
            form={metadata}
            job_type={field}
            checked={checked}
          />
        <% end %>
      </div>

      <% focus_options =
        if input_value(metadata, :first_manage) not in [nil, ""] do
          focus_options(input_value(metadata, :first_manage))
        else
          if input_value(metadata, :purpose) in ["School", "Non-profits"] do
            separate_focus_options(input_value(metadata, :purpose))
          else
            []
          end
        end %>
      <div :if={Enum.any?(focus_options)} class="font-bold text-lg my-5">
        Select what would you like to manage first?
      </div>
      <div :if={Enum.any?(focus_options)} class="grid grid-cols-3 gap-3">
        <%= for field <- focus_options do %>
          <% input_name = input_name(metadata, :first_focus) %>
          <% checked = input_value(metadata, :first_focus) == field %>
          <.custom_checkbox
            type="radio"
            name={input_name}
            form={metadata}
            job_type={field}
            checked={checked}
          />
        <% end %>
      </div>
    </.inputs_for>
    """
  end

  defp manage_options() do
    [
      "Non-profits",
      "Construction",
      "Software Development",
      "Finance",
      "Marketing",
      "Sales and CRM",
      "IT",
      "HR and Recruiting",
      "Education",
      "PMO",
      "Operations",
      "Design and Creative",
      "Product Management",
      "Legal",
      "Other"
    ]
  end

  defp focus_options(key) do
    %{
      "Non-profits" => [
        "Tasks Management",
        "Donor Management",
        "Portfolio Management",
        "Grants Management",
        "Emergency Response",
        "Requests and Approvals",
        "CRM",
        "Goals and Strategy",
        "Event Management",
        "Client Projects",
        "Resource Management",
        "Project Management",
        "Business Operations",
        "Volunteer Registration Management",
        "Other"
      ],
      "Construction" => [
        "Portfolio Management",
        "Client Projects",
        "Construction Scheduling",
        "Requests and Approvals",
        "Resource Management",
        "Task Management",
        "Project Management",
        "Goals and Strategy",
        "CRM",
        "Construction Planning",
        "Other"
      ],
      "Software Development" => [
        "Task Management",
        "Project Management",
        "Kanban",
        "Roadmap Planning",
        "Bugs Tracking",
        "Reporting",
        "Sprint Management",
        "Other"
      ],
      "Finance" => [
        "Task Management",
        "Project Management",
        "Client Projects",
        "Resource Management",
        "Business Operations",
        "Forecast Planning and Analytics",
        "CRM",
        "Billing and Invoices",
        "Goals and Strategy",
        "Accouting",
        "Budget Management",
        "Portfolio Management",
        "Requests and Approvals",
        "Other"
      ],
      "Marketing" => [
        "CRM",
        "Goals and Strategy",
        "Requests and Approvals",
        "Content Calendar",
        "Project Management",
        "Compaign Tracking",
        "Strategin Planning",
        "Marketing Operations",
        "Task Management",
        "Media Production",
        "Resource Management",
        "Portfolio Management",
        "Email Markeing",
        "Creative",
        "Event Management",
        "Social Media",
        "Other"
      ],
      "Sales and CRM" => [
        "Project Management",
        "Task Management",
        "Sales Pipeline",
        "Leads Capturing",
        "Marketing Activities",
        "Quotes and Invoices",
        "Lead Management",
        "Contact Management",
        "Other"
      ],
      "IT" => [
        "Goals and Strategy",
        "CRM",
        "IT Service Desk",
        "Tasks Management",
        "Portfolio Management",
        "Resource Management",
        "Project Management",
        "Tickets and Requests",
        "Software Development",
        "Knowledge Base",
        "Other"
      ],
      "HR and Recruiting" => [
        "Requests and Approvals",
        "Task Management",
        "Business Operations",
        "HR Services",
        "Employee Onboarding",
        "Onboarding and Offboarding",
        "Goals and Strategy",
        "Recruitment Pipeline",
        "Project Management",
        "Company Events",
        "Employee Directory",
        "Employee Experience",
        "Portfolio Management",
        "Recruiting and Talent Acquisition",
        "Resource Management",
        "HR Request",
        "CRM",
        "Other"
      ],
      "Education" => [
        "Requests And Approvals",
        "Individual Work",
        "Group Assignments",
        "Task Management",
        "Administrative Work",
        "CRM",
        "Goals And Strategy",
        "Student Organizations",
        "Business Operations",
        "Project Management",
        "Portfolio Management",
        "Academic Research",
        "Resource Management",
        "Curriculum And Syllabus Management",
        "Other"
      ],
      "PMO" => [
        "Project Planning",
        "Project Management",
        "CRM",
        "Portfolio Management",
        "Task Management",
        "Goals And Strategy",
        "Requests And Approvals",
        "Client Projects",
        "Customer Projects",
        "Resource Management",
        "Other"
      ],
      "Operations" => [
        "Project Management",
        "Task Management",
        "Marketing Operations",
        "Remote Work",
        "Portfolio Management",
        "Operations Processes",
        "Business Operations",
        "Requests And Approvals",
        "CRM",
        "Event Management",
        "Resource Management",
        "Goals And Strategy",
        "Other"
      ],
      "Design and Creative" => [
        "Resource Management",
        "Creative Planning",
        "Client Projects",
        "Portfolio Management",
        "Task Management",
        "Creative Requests",
        "Product Launches",
        "Media Production",
        "Project Management",
        "Content Calendar",
        "Requests And Approvals",
        "CRM",
        "Goals And Strategy",
        "Other"
      ],
      "Product Management" => [
        "Release Plan",
        "Task Management",
        "Project Management",
        "Features Backlog",
        "Roadmap Planning",
        "Other"
      ],
      "Legal" => [
        "Resource Management",
        "Requests And Approvals",
        "Project Management",
        "Legal Requests",
        "Task Management",
        "Goals And Strategy",
        "Portfolio Management",
        "Procurement",
        "Client Projects",
        "CRM",
        "Other"
      ],
      "Other" => [
        "Strategic Planning",
        "CRM",
        "Portfolio Management",
        "Project Management",
        "Digital Asset Management",
        "Task Management",
        "Sales Pipeline",
        "Client Projects",
        "Requests And Approvals",
        "Contact Management",
        "Project Planning",
        "Resource Management",
        "Goals And Strategy",
        "Business Operations",
        "Event Management",
        "Content Calendar",
        "Other"
      ]
    }
    |> Map.get(key)
  end

  defp separate_focus_options(key) do
    %{
      "School" => [
        "Requests And Approvals",
        "Individual Work",
        "Group Assignments",
        "Task Management",
        "Administrative Work",
        "CRM",
        "Goals And Strategy",
        "Student Organizations",
        "Business Operations",
        "Project Management",
        "Portfolio Management",
        "Academic Research",
        "Resource Management",
        "Curriculum And Syllabus Management",
        "Other"
      ],
      "Non-profits" => [
        "Task Management",
        "Donor Management",
        "Portfolio Management",
        "Grants Management",
        "Emergency Response",
        "Requests And Approvals",
        "CRM",
        "Goals And Strategy",
        "Event Management",
        "Client Projects",
        "Resource Management",
        "Project Management",
        "Business Operations",
        "Volunteers Registration Management",
        "Other"
      ]
    }
    |> Map.get(key)
  end

  defp get_role_options(purpose) do
    case purpose do
      "" ->
        []

      nil ->
        []

      "Work" ->
        [
          "Business Owner",
          "Team Leader",
          "Team Member",
          "Freelancer",
          "Director",
          "C-Level",
          "VP"
        ]

      "Personal" ->
        []

      "School" ->
        ["Undergraduate Student", "Graduate Student", "Faculty Member", "Other"]

      "Non-profits" ->
        ["Board Member", "Executive", "Employee", "Volunteer", "IT Staff", "Other"]

      _ ->
        []
    end
  end

  defp step(%{step: 3} = assigns) do
    ~H"""
    <.org_job_inputs {assigns} />
    """
  end

  defp assign_step(%{assigns: %{current_user: %{onboarding: onboarding}}} = socket) do
    if is_nil(onboarding.zipcode),
      do: assign_step(socket, 2),
      else: assign_step(socket, 3)
  end

  defp assign_step(socket, 2) do
    socket
    |> assign(
      step: 2,
      color_class: "bg-orange-inbox-200",
      step_title: "Tell us more about yourself",
      subtitle: "",
      page_title: "Onboarding Step 2"
    )
  end

  defp assign_step(socket, 3) do
    socket
    |> assign(
      step: 3,
      color_class: "bg-blue-gallery-200",
      step_title: "Customize your business",
      subtitle: "",
      page_title: "Onboarding Step 3"
    )
  end

  def optimized_container(assigns) do
    ~H"""
    <div class="flex items-stretch w-screen min-h-screen flex-wrap">
      <div class="lg:w-1/2 w-full flex flex-col justify-center px-8 lg:px-16 py-8">
        <div class="flex justify-between items-center">
          <%!-- <.icon name="logo-shoot-higher" class="w-32 h-12 sm:h-20 sm:w-48" /> --%>
          <div class="mb-5">
            <.steps step={@step} steps={@steps} for={:sign_up} />
          </div>
        </div>
        <%= render_slot(@inner_block) %>
      </div>
      <div class="lg:w-1/2 w-full flex flex-col items-center justify-center pl-8 lg:pl-16 bg-blue-planning-300">
        <%!-- <blockquote class="max-w-lg mx-auto py-8 lg:py-12">
          <p class="mb-4 text-white border-solid border-l-4 border-white pl-4">
            “I love the way that Todoplace flows and so easy to use! All the information I need is easily accessible and well organized. Putting together a proposal for a client is so simple and takes only a few clicks before it's ready to send off for signing and payment.”
          </p>
          <div class="flex items-center gap-4">
            <img
              src="https://uploads-ssl.webflow.com/61147776bffed57ff3e884ef/62f45d35be926e94d576f60c_emma.png"
              alt="Emma Thurgood"
            />
            <cite class="normal not-italic text-white">
              <span class="block font-bold not-italic">Emma Thurgood</span> www.emmathurgood.com
            </cite>
          </div>
        </blockquote> --%>
        <img
          class="object-cover object-top w-1/2"
          style="max-height:75vh;"
          src="/images/enter-password.png"
          alt="Todoplace Application"
        />
      </div>
    </div>
    """
  end

  def container(assigns) do
    ~H"""
    <div class={
      classes(["flex flex-col items-center justify-center w-screen min-h-screen p-5", @color_class])
    }>
      <div class="container px-6 pt-8 pb-6 bg-white rounded-lg shadow-md max-w-screen-sm sm:p-14">
        <div class="flex items-end justify-between sm:items-center">
          <%!-- <.icon name="logo-shoot-higher" class="w-32 h-12 sm:h-20 sm:w-48" /> --%>

          <a title="previous" phx-click="previous" class="cursor-pointer sm:py-2">
            <ul class="flex items-center">
              <%= for step <- 1..3 do %>
                <li class={
                  classes(
                    "block w-5 h-5 sm:w-3 sm:h-3 rounded-full ml-3 sm:ml-2",
                    %{@color_class => step == @step, "bg-gray-200" => step != @step}
                  )
                }>
                </li>
              <% end %>
            </ul>
          </a>
        </div>

        <h1 class="text-3xl font-bold mt-7 sm:leading-tight sm:mt-11"><%= @title %></h1>
        <h2 class="mt-2 mb-2 sm:mb-7 sm:mt-5 sm:text-lg"><%= @subtitle %></h2>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def save(%{assigns: %{step: step}} = socket, params, data \\ :skip) do
    save_multi(socket, params, data)
    |> then(fn
      {:ok, %{user: user}} ->
        socket
        |> assign(current_user: user)
        # |> assign_step(step + 1)
        |> assign_changeset()

      {:error, reason} ->
        socket |> assign(changeset: reason)
    end)

    # |> noreply()
  end
end
