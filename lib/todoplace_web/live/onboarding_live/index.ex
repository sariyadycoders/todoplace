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
    <.container step={@step} color_class={@color_class} title={@step_title} subtitle={@subtitle}>
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
    </.container>
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
      <.form_field
        label="What are you most interested in using Todoplace for?"
        error={:interested_in}
        prefix="Select one"
        f={onboarding}
      >
        <%= select(onboarding, :interested_in, [{"select one", nil}] ++ most_interested_select(),
          class: "select #{@input_class} truncate pr-8"
        ) %>
      </.form_field>
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
    """
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
      <div class="lg:w-1/3 w-full flex flex-col justify-center px-8 lg:px-16 py-8">
        <div class="flex justify-between items-center">
          <%!-- <.icon name="logo-shoot-higher" class="w-32 h-12 sm:h-20 sm:w-48" /> --%>
          <div class="mb-5">
            <.steps step={@step} steps={@steps} for={:sign_up} />
          </div>
        </div>
        <%= render_slot(@inner_block) %>
      </div>
      <div class="lg:w-2/3 w-full flex flex-col items-center justify-center pl-8 lg:pl-16 bg-blue-planning-300">
        <blockquote class="max-w-lg mx-auto py-8 lg:py-12">
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
        </blockquote>
        <%!-- <img
          class="mt-auto object-cover object-top w-full"
          style="max-height:75vh;"
          src="https://uploads-ssl.webflow.com/61147776bffed57ff3e884ef/62f45d6d8aae0229be8bafc7_large-hero.png"
          alt="Todoplace Application"
        /> --%>
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
