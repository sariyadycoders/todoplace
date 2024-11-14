defmodule TodoplaceWeb.OnboardingLive.ThreeMonth.Index do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: :onboarding]

  require Logger

  alias Todoplace.{
    Subscriptions,
    Subscriptions,
    Payments,
    Accounts,
    Accounts.User.Promotions
  }

  import TodoplaceWeb.OnboardingLive.Shared,
    only: [
      signup_container: 1,
      signup_deal: 1,
      form_field: 1,
      save_final: 3,
      save_multi: 3,
      assign_changeset: 3,
      org_job_inputs: 1,
      most_interested_select: 0,
      country_info: 1,
      countries: 0,
      states_or_province: 1,
      field_for: 1
    ]

  @impl true
  def mount(_params, _session, socket) do
    %{value: three_month} = Todoplace.AdminGlobalSettings.get_settings_by_slug("three_month")

    socket
    |> assign(:main_class, "bg-gray-100")
    |> assign(:step_total, 4)
    |> assign_step()
    |> assign(:state, nil)
    |> assign(:country, nil)
    |> assign(
      :promotion_code,
      if(Subscriptions.maybe_return_promotion_code_id?(three_month),
        do: three_month,
        else: nil
      )
    )
    |> assign(:stripe_elements_loading, false)
    |> assign(:stripe_publishable_key, Application.get_env(:stripity_stripe, :publishable_key))
    |> assign_changeset(%{}, :three_month)
    |> ok()
  end

  @impl true
  def handle_params(
        %{
          "redirect_status" => "succeeded",
          "state" => state,
          "country" => country
        },
        _url,
        socket
      ) do
    socket
    |> assign(:stripe_elements_loading, false)
    |> assign(:state, state)
    |> assign(:country, country)
    |> assign_step(3)
    |> noreply()
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket
    |> noreply()
  end

  @impl true
  def handle_event("previous", %{}, %{assigns: %{step: 2}} = socket), do: socket |> noreply()

  @impl true
  def handle_event("previous", %{}, %{assigns: %{step: step}} = socket) do
    socket |> assign_step(step - 1) |> assign_changeset(%{}, :three_month) |> noreply()
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    socket |> assign_changeset(params, :three_month) |> noreply()
  end

  @impl true
  def handle_event("validate", _params, socket) do
    socket |> assign_changeset(%{}, :three_month) |> noreply()
  end

  @impl true
  def handle_event("save", %{"user" => params}, %{assigns: %{step: 4}} = socket) do
    save_final(socket, params, :three_month)
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    save(socket, params)
  end

  @impl true
  def handle_event("save", _params, %{assigns: %{step: 2}} = socket), do: noreply(socket)

  @impl true
  def handle_event(
        "stripe-elements-success",
        _params,
        %{assigns: %{current_user: current_user, promotion_code: promotion_code}} = socket
      ) do
    stripe_params = %{
      customer: Subscriptions.user_customer_id(current_user),
      start_date: "now",
      phases: [
        %{
          items: [
            %{
              price: Subscriptions.get_subscription_plan("month").stripe_price_id,
              quantity: 3
            }
          ],
          coupon: Subscriptions.maybe_return_promotion_code_id?(promotion_code),
          iterations: 1
        },
        %{
          items: [
            %{
              price: Subscriptions.get_subscription_plan("month").stripe_price_id,
              quantity: 1
            }
          ],
          iterations: 2,
          trial: true
        },
        %{
          items: [
            %{
              price: Subscriptions.get_subscription_plan("month").stripe_price_id,
              quantity: 1
            }
          ],
          iterations: 1
        }
      ],
      expand: [
        "subscription",
        "subscription.latest_invoice.payment_intent",
        "subscription.pending_setup_intent"
      ]
    }

    case Payments.create_subscription_schedule(stripe_params) do
      {:ok, %Stripe.SubscriptionSchedule{subscription: subscription}} ->
        Subscriptions.handle_stripe_subscription(subscription)

        Promotions.insert_or_update_promotion(current_user, %{
          slug: promotion_code,
          state: :purchased,
          name: "Three Month"
        })

        socket
        |> assign(:stripe_elements_loading, false)
        |> put_flash(:success, "Subscription and payment added!")

      {:error, error} ->
        Logger.error("Error creation subscription schedule: #{inspect(error)}")

        socket
        |> assign(:stripe_elements_loading, false)
        |> put_flash(
          :error,
          "Sorry - something went wrong! Confirm your payment and information is correct or reach out to Customer Success."
        )
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "stripe-elements-create",
        %{"address" => %{"value" => %{"address" => address}}} = _params,
        %{assigns: %{current_user: current_user, promotion_code: promotion_code}} = socket
      ) do
    customer_id = Subscriptions.user_customer_id(current_user, %{address: address})

    case Payments.setup_intent(%{
           customer: customer_id,
           usage: "off_session",
           automatic_payment_methods: %{enabled: true}
         }) do
      {:ok, %{client_secret: client_secret}} ->
        return =
          build_return(
            client_secret,
            address,
            promotion_code,
            "setup"
          )

        socket
        |> assign(
          :current_user,
          Accounts.get_user_by_stripe_customer_id(customer_id)
        )
        |> push_event("stripe-elements-confirm", return)

      {:error, error} ->
        Logger.error("Error creating subscription: #{inspect(error)}")

        socket
        |> assign(:stripe_elements_loading, false)
        |> put_flash(:error, "Payment method didn't work. Please try again")
    end
    |> noreply()
  end

  @impl true
  def handle_event("stripe-elements-loading", _params, socket) do
    socket |> assign(:stripe_elements_loading, true) |> noreply()
  end

  @impl true
  def handle_event("stripe-elements-error", %{"error" => error}, socket) do
    Logger.error("Error creating subscription: #{inspect(error)}")

    socket
    |> assign(:stripe_elements_loading, false)
    |> put_flash(
      :error,
      "Sorry - something went wrong! Confirm your payment and information is correct or reach out to Customer Success."
    )
    |> noreply()
  end

  @impl true
  def handle_event("stripe-elements-error", _params, socket) do
    socket
    |> assign(:stripe_elements_loading, false)
    |> put_flash(
      :error,
      "Sorry - something went wrong! Confirm your payment and information is correct or reach out to Customer Success."
    )
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
      <.form :let={f} for={@changeset} phx-change="validate" phx-submit="save" id={"onboarding-step-#{@step}"} class={classes("" , %{"pointer-events-none" => @stripe_elements_loading})}>
        <.step f={f} {assigns} />
      </.form>
    """
  end

  defp step(%{step: 2} = assigns) do
    ~H"""
      <.signup_container {assigns} show_logout?={true} left_classes="p-8 bg-purple-marketing-300 text-white order-2 sm:order-1">
        <h2 class="text-3xl md:text-4xl font-bold text-center mb-8">Todoplace is here to help you achieve success on your terms</h2>
        <blockqoute class="max-w-lg mt-auto mx-auto block mt-8">
          <p class="mb-4 text-white border-solid border-l-4 border-white pl-4">
            "Jane has been a wonderful mentor! With her help I’ve learned the importance of believing in myself and my work. She has taught me that it is imperative to be profitable at every stage of my photography journey to ensure I’m set up for lasting success. Jane has also given me the tools I need to make sure I’m charging enough to be profitable. She is always there to answer my questions and cheer me on. Jane has played a key role in my growth as a photographer and business owner! I wouldn’t be where I am without her!”
          </p>
          <div class="flex items-center gap-4">
            <img src={static_path(@socket, "/images/mastermind-quote.png")} loading="lazy" alt="Logo for Jess Allen Photography" class="w-12 h-12 object-contain" />
            <cite class="normal not-italic text-white"><span class="block font-bold not-italic">Jess Allen</span>
              jessallenphotography.com</cite>
          </div>
        </blockqoute>
        <blockqoute class="max-w-lg mx-auto mt-6 block">
          <p class="mb-4 text-white border-solid border-l-4 border-white pl-4">
            "The mobile design on Todoplace is GENIUS! I can operate it fully from my phone in a mobile friendly version - no more ‘this is not supported by the app at this time!’”
          </p>
          <div class="flex items-center gap-4">
            <img src="https://assets-global.website-files.com/61147776bffed57ff3e884ef/629e8d41780f4f5411f43fc9_adrienne.webp" loading="lazy" alt="Logo for Adrienne DeMarco" class="w-12 h-12 object-contain rounded-full" />
            <cite class="normal not-italic text-white"><span class="block font-bold not-italic">Adrienne DeMarco</span>
              apdphotography.com</cite>
          </div>
        </blockqoute>
        <%= if @stripe_elements_loading do %>
          <div class="fixed bg-base-300/75 backdrop-blur-md pointer-events-none w-full h-full z-50 top-0 left-0 flex items-center justify-center">
            <.icon class="animate-spin w-8 h-8 mr-2 text-white" name="loader"/>
            <p class="font-bold">Processing payment…</p>
          </div>
        <% end %>
        <:right_panel>
          <.signup_deal original_price={Money.new(10500, :USD)} price={Money.new(6000, :USD)} note="Save $45 on a three-month subscription to move over to Todoplace" />
          <p class="text-md text-gray-400 italic text-center mt-2">Your card will be charged the discounted price</p>
          <div
            phx-update="ignore"
            class="my-6"
            phx-hook="StripeElements"
            id="stripe-elements"
            data-publishable-key={@stripe_publishable_key}
            data-name={@current_user.name}
            data-email={@current_user.email}
            data-type="setup"
            data-return-url={"#{~p"/"}#{~p"/onboarding/mastermind"}"}
          >
            <div id="address-element"></div>
            <div id="payment-element" class="mt-2"></div>
          </div>
          <.step_footer {assigns} />
        </:right_panel>
      </.signup_container>
    """
  end

  defp step(%{step: 3} = assigns) do
    assigns = assign(assigns, input_class: "p-4")

    ~H"""
      <.signup_container {assigns} show_logout?={true} left_classes="p-8 bg-purple-marketing-300 text-white order-2 sm:order-1">
        <div class="flex justify-center mt-12">
          <img src={static_path(@socket, "/images/mastermind-clientbooking.png")} loading="lazy" alt="Todoplace Client booking feature" class="max-w-full" />
        </div>
        <blockqoute class="max-w-lg mt-auto mx-auto py-8 lg:py-12">
          <p class="mb-4 text-white border-solid border-l-4 border-white pl-4">
            “I love the way that Todoplace flows and so easy to use! All the information I need is easily accessible and well organized. Putting together a proposal for a client is so simple and takes only a few clicks before it's ready to send off for signing and payment.”
          </p>
          <div class="flex items-center gap-4">
            <img src={static_path(@socket, "/images/mastermind-quote2.png")} loading="lazy" alt="Logo for Emma Thurgood" class="w-12 h-12 object-contain" />
            <cite class="normal not-italic text-white"><span class="block font-bold not-italic">Emma Thurgood</span>
            emmathurgood.com</cite>
          </div>
        </blockqoute>
        <:right_panel>
          <%= for org <- inputs_for(@f, :organization) do %>
            <%= hidden_inputs_for org %>
            <.form_field label="What’s the name of your photography business?" error={:name} prefix="Photography business name" f={org} mt={0} >
              <%= input org, :name, phx_debounce: "500", placeholder: "Jack Nimble Photography", class: @input_class %>
              <p class="italic text-sm text-gray-400 mt-2"><%= url(~p"/photographer/#{input_value(org, :slug)}") %></p>
            </.form_field>
          <% end %>
          <%= for onboarding <- inputs_for(@f, :onboarding) do %>
            <%= hidden_input onboarding, :promotion_code, value: @promotion_code %>
            <.form_field label="Are you a full-time or part-time photographer?" error={:schedule} f={onboarding} >
              <%= select onboarding, :schedule, %{"Full-time" => :full_time, "Part-time" => :part_time}, class: "select #{@input_class}" %>
            </.form_field>

            <.form_field label="How many years have you been a photographer?" error={:photographer_years} f={onboarding} >
              <%= input onboarding, :photographer_years, type: :number_input, phx_debounce: 500, min: 0, placeholder: "e.g. 0, 1, 2, etc.", class: @input_class %>
            </.form_field>

            <%= hidden_input onboarding, :welcome_count, value: 0 %>

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

            <%= if is_nil(@country) || is_nil(@state) do %>
              <% info = country_info(input_value(onboarding, :country)) %>
              <div class={classes("grid gap-4 mb-8", %{"sm:grid-cols-2" => Map.has_key?(info, :state_label)})}>
                <.form_field label="What’s your country?" error={:country} f={onboarding}>
                  <%= select(onboarding, :country, [{"United States", :US}] ++ countries(),
                    class: "select #{@input_class}"
                  ) %>
                </.form_field>

                <%= if Map.has_key?(info, :state_label) do %>
                  <.form_field label={info.state_label} error={:state} f={onboarding}>
                    <%= select(
                      onboarding,
                      field_for(input_value(onboarding, :country)),
                      [{"select one", nil}] ++ states_or_province(input_value(onboarding, :country)),
                      class: "select #{@input_class}"
                    ) %>
                  </.form_field>
                <% end %>
              </div>
            <% else %>
              <%= if @country == "CA" do %>
                <%= hidden_input onboarding, :province, value: @state %>
              <% else %>
                <%= hidden_input onboarding, :state, value: @state %>
              <% end %>
              <%= hidden_input onboarding, :country, value: @country %>
            <% end %>

          <% end %>
          <.step_footer {assigns} />
        </:right_panel>
      </.signup_container>
    """
  end

  defp step(%{step: 4} = assigns) do
    ~H"""
      <.signup_container {assigns} show_logout?={true} left_classes="p-8 pb-0 pr-0 bg-purple-marketing-300 text-white order-2 sm:order-1">
        <h2 class="text-3xl md:text-4xl font-bold text-center mb-8">Your <span class="underline underline-offset-1 text-decoration-blue-planning-300">all-in-one</span> photography business software with coaching included.</h2>
        <img src={static_path(@socket, "/images/mastermind-dashboard.png")} loading="lazy" alt="Todoplace Client booking feature" />
        <:right_panel>
          <.org_job_inputs {assigns} />
          <.step_footer {assigns} />
        </:right_panel>
      </.signup_container>
    """
  end

  defp step_footer(assigns) do
    ~H"""
    <div class="flex items-center justify-between mt-5 sm:justify-end sm:mt-auto gap-4">
      <%= if @step > 3 do %>
        <button type="button" phx-click="previous" class="flex-grow px-6 sm:flex-grow-0 btn-secondary sm:px-8">
          Back
        </button>
      <% end %>
      <button type="submit" phx-disable-with="Saving…" disabled={if @step === 2 do @stripe_elements_loading else !@changeset.valid? || @stripe_elements_loading end} id={if @step === 2 do "payment-element-submit" end} class="flex-grow px-6 btn-primary sm:px-8">
        <%= if @stripe_elements_loading do %>
          Saving…
        <% else %>
          <%= if @step == 4, do: "Finish", else: "Next" %>
        <% end %>
      </button>
    </div>
    """
  end

  defp assign_step(
         %{assigns: %{current_user: %{stripe_customer_id: nil, subscription: nil}}} = socket
       ) do
    assign_step(socket, 2)
  end

  defp assign_step(
         %{assigns: %{current_user: %{stripe_customer_id: _, subscription: nil}}} = socket
       ) do
    assign_step(socket, 2)
  end

  defp assign_step(%{assigns: %{current_user: %{onboarding: onboarding}}} = socket) do
    if is_nil(onboarding.photographer_years) &&
         is_nil(onboarding.schedule),
       do: assign_step(socket, 3),
       else: assign_step(socket, 4)
  end

  defp assign_step(socket, 2) do
    socket
    |> assign(
      step: 2,
      step_title: "Payment Details",
      page_title: "Onboarding Step 2"
    )
  end

  defp assign_step(socket, 3) do
    socket
    |> assign(
      step: 3,
      step_title: "Create your Todoplace profile",
      page_title: "Onboarding Step 3"
    )
  end

  defp assign_step(socket, 4) do
    socket
    |> assign(
      step: 4,
      step_title: "Customize your business",
      page_title: "Onboarding Step 4"
    )
  end

  defp save(%{assigns: %{step: step}} = socket, params, data \\ :skip) do
    save_multi(socket, params, data)
    |> then(fn
      {:ok, %{user: user}} ->
        socket
        |> assign(current_user: user)
        |> assign_step(step + 1)
        |> assign_changeset(%{}, :three_month)

      {:error, reason} ->
        socket |> assign(changeset: reason)
    end)
    |> noreply()
  end

  defp build_return(client_secret, address, promotion_code, type) do
    %{
      type: type,
      client_secret: client_secret,
      promotion_code: promotion_code,
      state:
        if Map.get(address, "country") == "US" do
          Map.get(address, "state")
        else
          "Non-US"
        end,
      country: Map.get(address, "country")
    }
  end
end
