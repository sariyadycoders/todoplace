defmodule TodoplaceWeb.UserRegisterLive do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "onboarding"]

  alias Todoplace.{Accounts, Accounts.User, InviteToken}
  import TodoplaceWeb.OnboardingLive.Index, only: [optimized_container: 1]

  import Todoplace.Subscriptions,
    only: [get_subscription_plan_metadata: 0, get_subscription_plan_metadata: 1]

  import TodoplaceWeb.OnboardingLive.Shared, only: [signup_container: 1, signup_deal: 1]

  @steps [1, 2, 3, 4]

  @impl true
  def mount(%{"token" => token} = params, session, socket) do
      %{value: black_friday_timer_end} =
      Todoplace.AdminGlobalSettings.get_settings_by_slug("black_friday_timer_end")

    case InviteToken.validate_invite_token(token) do
      {:ok, invitation} ->
        email = invitation.email
        organization_id = invitation.organization_id

        socket
        |> assign(:main_class, "bg-gray-100")
        |> assign_defaults(session)
        |> assign(:onboarding_type, nil)
        |> assign(step: 1, steps: @steps)
        |> assign(:subscription_plan_metadata, get_subscription_plan_metadata())
        |> assign(:black_friday_timer_end, black_friday_timer_end)
        |> assign(:page_title, "Sign Up")
        |> assign(:meta_attrs, %{
          description:
            "This is going to be a game changer! Get signed up and start growing your business. Register with Todoplace and start managing, marketing, and monetizing your photography business today."
        })
        |> assign_changeset(%{"email" => email, "organization_id" => organization_id })
        |> assign(:invitation, invitation)
        |> assign(:token, token)
        |> assign_trigger_submit()
        |> ok()

      _ ->
      socket
      |> assign(:invitation, nil)
      |> assign(:token, nil)
      |> assign(:changeset, Accounts.change_user_registration(%User{}))
      |> noreply()
    end
  end

  def mount(params, session, socket) do
    default_mount(params, session, socket)
  end

  defp default_mount(params, session, socket) do
    %{value: black_friday_timer_end} =
      Todoplace.AdminGlobalSettings.get_settings_by_slug("black_friday_timer_end")

    socket
    |> assign(:main_class, "bg-gray-100")
    |> assign_defaults(session)
    |> assign(:onboarding_type, nil)
    |> assign(step: 1, steps: @steps)
    |> assign(:subscription_plan_metadata, get_subscription_plan_metadata())
    |> assign(:black_friday_timer_end, black_friday_timer_end)
    |> assign(:page_title, "Sign Up")
    |> assign(:meta_attrs, %{
      description:
        "This is going to be a game changer! Get signed up and start growing your business. Register with Todoplace and start managing, marketing, and monetizing your photography business today."
    })
    |> assign(:invitation, nil)
    |> assign_changeset()
    |> assign_trigger_submit()
    |> ok()
  end

  @impl true
  def handle_params(%{"code" => code}, _uri, socket) do
    socket
    |> assign(:subscription_plan_metadata, get_subscription_plan_metadata(code))
    |> noreply()
  end

  @impl true
  def handle_params(%{"onboarding_type" => onboarding_type}, _uri, socket) do
    socket
    |> assign(:onboarding_type, onboarding_type)
    |> noreply()
  end

  def handle_params(_params, _uri, socket), do: noreply(socket)

  @impl true
  def handle_event("validate", %{"user" => %{"trigger_submit" => "true"}}, socket),
    do: noreply(socket)

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    params = Map.put(params, "onboarding_flow_source", [socket.assigns.onboarding_type])

    socket |> assign_changeset(params, :validate) |> noreply()
  end

  @impl true
  def handle_event("previous", %{}, socket), do: noreply(socket)

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    user_params = Map.put(user_params, "onboarding_flow_source", [socket.assigns.onboarding_type])

    socket
    |> assign_changeset(user_params, :validate)
    |> assign_trigger_submit()
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
      <.onboarding_view {assigns} />
    """
  end

  defp onboarding_view(%{onboarding_type: nil} = assigns) do
    ~H"""
      <.optimized_container step={@step} steps={@steps} color_class="bg-blue-planning-200">
        <.signup_hooks />
        <h1 class="text-3xl font-bold sm:leading-tight mt-2"><%= @subscription_plan_metadata.signup_title %></h1>
        <h2 class="text-base mt-4 font-normal"><%= @subscription_plan_metadata.signup_description %> or <%= link "log in", to: ~p"/users/log_in", class: "underline text-blue-planning-300" %>.</h2>
        <.signup_form {assigns} />
      </.optimized_container>
    """
  end

  defp onboarding_view(%{onboarding_type: "mastermind"} = assigns) do
    ~H"""
      <.signup_container {assigns} step={1} step_total={length(@steps)} step_title="Let’s get to know you" left_classes="p-8 pb-0 bg-purple-marketing-300 text-white flex flex-col">
        <h2 class="text-3xl md:text-3xl font-bold text-center mb-2">
          Gift Yourself Success and Support!
        </h2>
        <h3 class="text-xl text-center mb-4 italic">Sign up and get a full year of Todoplace for $350</h3>
        <p class="text-center">Make the switch to Todoplace in 2024—get the software, support, and education you need to grow your business!</p>
        <ul class="mb-8 space-y-2">
          <li class="flex gap-2 font-bold font-italic"><.icon name="checkcircle" class="h-4 w-4 flex-shrink-0 mt-1.5" /> One-year of Todoplace’s all-in-one software</li>
          <li class="flex gap-2"><.icon name="checkcircle" class="h-4 w-4 flex-shrink-0 mt-1.5" /> 12-months of the Business Mastermind</li>
          <li class="flex gap-2"><.icon name="checkcircle" class="h-4 w-4 flex-shrink-0 mt-1.5" /> Best-in-the- business customer support</li>
          <li class="flex gap-2"><.icon name="checkcircle" class="h-4 w-4 flex-shrink-0 mt-1.5" /> Resources that will help you market, manage, and monetize your business</li>
        </ul>
        <img class="mt-auto" src={static_path(@socket, "/images/mastermind-hero.png")} loading="lazy" alt="Images of the Todoplace App" />
        <:right_panel>
          <.signup_hooks />
          <.signup_form {assigns} form_classes="flex-grow" />
          <div class="flex items-center justify-center mt-4 gap-2">
            <a class="link" href="/users/log_in">Login</a>
          </div>
        </:right_panel>
      </.signup_container>
    """
  end

  defp onboarding_view(%{onboarding_type: "three_month"} = assigns) do
    ~H"""
      <.signup_container {assigns} step={1} step_total={length(@steps)} step_title="Let’s get to know you" left_classes="p-8 pb-0 bg-purple-marketing-300 text-white">
        <h2 class="text-3xl md:text-4xl font-bold mb-2 text-center">
          Ditch the overwhelm! Sign up for 3 months of Todoplace for only $60!
        </h2>
        <p class="text-center">Make the switch to Todoplace in 2024—get the software, support, and education you need to grow your business!</p>
        <div class="max-w-md mx-auto my-8">
          <.signup_deal original_price={Money.new(10500, :USD)} price={Money.new(6000, :USD)} note="Save $45 on a three-month subscription to move over to Todoplace" />
        </div>
        <ul class="mb-8 space-y-2">
          <li class="flex gap-2"><.icon name="checkcircle" class="h-4 w-4 flex-shrink-0 mt-1.5" /> 3 months of Todoplace’s all-in-one software</li>
          <li class="flex gap-2"><.icon name="checkcircle" class="h-4 w-4 flex-shrink-0 mt-1.5" /> Best-in-the- business customer support</li>
          <li class="flex gap-2"><.icon name="checkcircle" class="h-4 w-4 flex-shrink-0 mt-1.5" /> Resources that will help you market, manage, and monetize your business</li>
        </ul>
        <img src={static_path(@socket, "/images/mastermind-hero.png")} loading="lazy" alt="Images of the Todoplace App" />
        <:right_panel>
          <.signup_hooks />
          <.signup_form {assigns} form_classes="flex-grow" />
          <div class="flex items-center justify-center mt-4 gap-2">
            <a class="link" href="/users/log_in">Login</a>
          </div>
        </:right_panel>
      </.signup_container>
    """
  end

  defp signup_form(assigns) do
    assigns =
      Enum.into(assigns, %{
        form_classes: ""
      })

    ~H"""
      <div id="loader" class="hidden flex items-center justify-center">
          <div class="animate-spin rounded-full h-32 w-32 border-b-2 border-gray-900"></div>
      </div>
      <a id="google-login-button" href={~p"/auth/google"} phx-hook="ShowLoader" class="flex items-center justify-center w-full mt-8 text-center btn-primary">
        <.icon name="google" width="25" height="24" class="mr-4" />
        Continue with Google
      </a>
      <p class="m-6 text-center">or</p>
      <.form :let={f} for={@changeset} action={~p"/users/register"} phx-change="validate" phx-submit="save" phx-trigger-action={@trigger_submit} class={"flex flex-col #{@form_classes}"}>
        <%= hidden_input f, :trigger_submit, value: @trigger_submit %>
        <%= hidden_input f, :onboarding_flow_source, value: @onboarding_type %>
        <%= if @invitation do %>
          <%= labeled_input f, :email, value: @invitation.email, readonly: true, phx_debounce: "500", wrapper_class: "mt-4" %>
          <%= hidden_input f, :organization_id, value: @invitation.organization_id, readonly: true, phx_debounce: "500", wrapper_class: "mt-4" %>

        <% else %>
          <%= labeled_input f, :email, type: :email_input, placeholder: "jack.nimble@example.com", phx_debounce: "500", wrapper_class: "mt-4" %>
        <% end %>

        <%= labeled_input f, :name, placeholder: "Jack Nimble", phx_debounce: "500", label: "Your first & last name", autocomplete: "name" %>
        <.live_component module={TodoplaceWeb.PasswordFieldComponent} f={f} id={:register_password} placeholder="something secret" />

        <p class="text-sm text-gray-400 mt-6 sm:pr-6 mb-8">By signing up you agree to our
          <a href={"#{base_url(:marketing)}privacy-policy"} target="_blank" rel="noopener noreferrer" class="border-b border-gray-400">Privacy Policy</a> and
          <a href={"#{base_url(:marketing)}terms-conditions"} target="_blank" rel="noopener noreferrer" class="border-b border-gray-400">Terms</a>
        </p>

        <div class="flex mt-auto">
          <%= submit "Sign up",
            class: "btn-primary sm:flex-1 px-6 sm:px-10 flex-grow",
            disabled: !@changeset.valid?,
            phx_disable_with: "Saving..."
          %>
        </div>
      </.form>
    """
  end

  defp signup_hooks(assigns) do
    ~H"""
      <div id="onboarding-cookie" phx-hook="OnboardingCookie"></div>
      <div phx-hook="HandleTrialCode" id="handle-trial-code" data-handle="save"></div>
      <%!-- <div phx-hook="Onboardingbrowser" id="Onboardingbrowser"></div> --%>
    """
  end

  defp assign_trigger_submit(%{assigns: %{changeset: changeset}} = socket) do
    socket |> assign(trigger_submit: changeset.valid?)
  end

  defp assign_changeset(socket, params \\ %{}, action \\ nil) do
    socket
    |> assign(
      changeset: Accounts.change_user_registration(%User{}, params) |> Map.put(:action, action)
    )
  end
end
