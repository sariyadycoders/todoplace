defmodule TodoplaceWeb.PackageLive.WizardComponent do
  @moduledoc false

  use TodoplaceWeb, :live_component

  import Phoenix.Component

  alias Ecto.Changeset

  alias Todoplace.{
    Repo,
    Package,
    Profiles,
    Packages,
    Packages.Multiplier,
    Packages.Download,
    Packages.PackagePricing,
    Contracts,
    Contract,
    PackagePaymentSchedule,
    PackagePayments,
    Shoot,
    Questionnaire,
    GlobalSettings,
    Currency
  }

  import Todoplace.Utils, only: [products_currency: 0]
  import TodoplaceWeb.Shared.Quill, only: [quill_input: 1]
  import TodoplaceWeb.GalleryLive.Shared, only: [steps: 1]
  import TodoplaceWeb.Live.Calendar.Shared, only: [is_checked: 2]
  import TodoplaceWeb.PackageLive.PackagesSearchComponent, only: [packages_search_component: 1]

  import TodoplaceWeb.PackageLive.Shared,
    only: [
      package_row: 1,
      package_basic_fields: 1,
      digital_download_fields: 1,
      package_print_credit_fields: 1,
      current: 1,
      assign_turnaround_weeks: 1,
      digitals_total: 1
    ]

  import TodoplaceWeb.ClientBookingEventLive.Shared,
    only: [
      blurred_thumbnail: 1
    ]

  import TodoplaceWeb.Shared.ImageUploadInput, only: [image_upload_input: 1]

  import TodoplaceWeb.LiveModal, only: [close_x: 1, footer: 1]

  @all_fields Package.__schema__(:fields)

  defmodule CustomPayments do
    @moduledoc "For setting payments on last step"
    use Ecto.Schema
    import Ecto.Changeset
    alias TodoplaceWeb.PackageLive.WizardComponent

    @primary_key false
    embedded_schema do
      field(:schedule_type, :string)
      field(:fixed, :boolean)
      field(:total_price, Money.Ecto.Map.Type)
      field(:remaining_price, Money.Ecto.Map.Type)
      embeds_many(:payment_schedules, PackagePaymentSchedule)
    end

    def changeset(attrs, default_payment_changeset \\ nil) do
      fixed = %__MODULE__{} |> cast(attrs, [:fixed]) |> Changeset.get_field(:fixed)

      %__MODULE__{}
      |> cast(attrs, [:total_price, :remaining_price, :fixed, :schedule_type])
      |> cast_embed(:payment_schedules,
        with: &PackagePaymentSchedule.changeset(&1, &2, default_payment_changeset, fixed, attrs),
        required: true
      )
      |> validate_schedule_date(default_payment_changeset)
      |> validate_required([:schedule_type, :fixed])
      |> validate_total_amount()
    end

    defp validate_schedule_date(changeset, default_payment_changeset) do
      {schedules_changeset, _} =
        changeset
        |> Changeset.get_change(:payment_schedules)
        |> Enum.reduce({[], []}, fn payment, {schedules, acc} ->
          payment = transform_to_schedule_date(payment, default_payment_changeset)

          schedules_changeset =
            if Enum.any?(acc) do
              Enum.with_index(acc, fn x_schedule_date, index ->
                compare_and_validate(payment, x_schedule_date, index, length(acc))
              end)
              |> List.flatten()
              |> List.first()
              |> then(fn
                nil -> schedules ++ [payment]
                schedule -> schedules ++ [schedule]
              end)
            else
              schedules ++ [payment]
            end

          schedule_date = Changeset.get_field(payment, :schedule_date)
          {schedules_changeset, if(schedule_date, do: acc ++ [schedule_date], else: acc)}
        end)

      Changeset.put_change(changeset, :payment_schedules, schedules_changeset |> List.flatten())
    end

    defp compare_and_validate(changeset, x_schedule_date, index, field_index) do
      case Date.compare(Changeset.get_field(changeset, :schedule_date), x_schedule_date) do
        :lt ->
          add_error(
            changeset,
            :schedule_date,
            "Payment #{field_index + 1} must be after Payment #{index + 1}"
          )

        :eq ->
          add_error(
            changeset,
            :schedule_date,
            "Payment #{field_index + 1} and Payment #{index + 1} can't be same"
          )

        _ ->
          []
      end
    end

    defp validate_total_amount(changeset) do
      remaining = remaining_to_collect(changeset)

      if Money.zero?(remaining) do
        changeset
      else
        changeset
        |> add_error(:remaining_price, "is not valid")
      end
      |> Changeset.put_change(:remaining_price, remaining)
    end

    defp remaining_to_collect(payments_changeset) do
      %{
        fixed: fixed,
        total_price: %{currency: currency} = total_price,
        payment_schedules: payments
      } = payments_changeset |> current()

      initial_price = WizardComponent.new_money(currency)

      total_collected =
        payments
        |> Enum.reduce(initial_price, fn payment, acc ->
          if fixed do
            Money.add(acc, payment.price || initial_price)
          else
            Money.add(acc, from_percentage(payment.percentage, total_price))
          end
        end)

      Money.subtract(total_price, total_collected.amount)
    end

    defp from_percentage(nil, %{currency: currency}), do: WizardComponent.new_money(currency)

    defp from_percentage(price, total_price) do
      Money.divide(total_price, 100) |> List.first() |> Money.multiply(price)
    end

    defp transform_to_schedule_date(changeset, default_payment_changeset) do
      shoot_date = get_shoot_date(Changeset.get_field(changeset, :shoot_date))

      schedule_date =
        case Changeset.get_field(changeset, :interval) do
          true ->
            transform_text_to_date(Changeset.get_field(changeset, :due_interval), shoot_date)

          _ ->
            transform_text_to_date(changeset, default_payment_changeset, shoot_date)
        end

      Changeset.put_change(changeset, :schedule_date, schedule_date)
    end

    defp transform_text_to_date("" <> due_interval, shoot_date) do
      cond do
        String.contains?(due_interval, "6 Months Before") -> Timex.shift(shoot_date, months: -6)
        String.contains?(due_interval, "1 Month Before") -> Timex.shift(shoot_date, months: -1)
        String.contains?(due_interval, "Week Before") -> Timex.shift(shoot_date, days: -7)
        String.contains?(due_interval, "Day Before") -> Timex.shift(shoot_date, days: -1)
        true -> Timex.now() |> DateTime.truncate(:second)
      end
    end

    defp transform_text_to_date(changeset, default_payment_changeset, shoot_date) do
      interval =
        if default_payment_changeset,
          do:
            PackagePaymentSchedule.get_default_payment_schedules_values(
              default_payment_changeset,
              :interval,
              get_field(changeset, :payment_field_index)
            ),
          else: false

      due_at = Changeset.get_field(changeset, :due_at)

      if due_at || (Changeset.get_field(changeset, :shoot_date) && interval) do
        if due_at, do: due_at |> Timex.to_datetime(), else: shoot_date
      else
        last_shoot_date = get_shoot_date(Changeset.get_field(changeset, :last_shoot_date))
        count_interval = Changeset.get_field(changeset, :count_interval)
        count_interval = if count_interval, do: count_interval |> String.to_integer(), else: 1
        time_interval = Changeset.get_field(changeset, :time_interval)

        time_interval =
          if(time_interval, do: time_interval <> "s", else: "Days")
          |> String.downcase()
          |> String.to_atom()

        if(Changeset.get_field(changeset, :shoot_interval) == "Before 1st Shoot",
          do: Timex.shift(shoot_date, [{time_interval, -count_interval}]),
          else: Timex.shift(last_shoot_date, [{time_interval, -count_interval}])
        )
      end
    end

    defp get_shoot_date(shoot_date),
      do: if(shoot_date, do: shoot_date, else: Packages.future_date())
  end

  @impl true
  def update(
        %{booking_event: %{package_template: package_template}} = assigns,
        socket
      )
      when not is_nil(package_template) do
    assigns =
      Enum.into(assigns, %{
        package: package_template
      })

    socket
    |> assign(assigns)
    |> assign_new(:booking_event, fn -> nil end)
    |> assign_new(:job, fn -> nil end)
    |> assign(is_template: assigns |> Map.get(:booking_event) |> is_nil())
    |> assign_defaults()
    |> ok()
  end

  @impl true
  def update(
        %{booking_event: _} = assigns,
        socket
      ) do
    socket
    |> assign(assigns)
    |> assign_new(:booking_event, fn -> nil end)
    |> assign(is_template: assigns |> Map.get(:booking_event) |> is_nil())
    |> assign_defaults()
    |> ok()
  end

  @impl true
  def update(%{templates: templates}, socket) do
    socket |> assign(:templates, templates) |> ok
  end

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:job, fn -> nil end)
    |> assign(is_template: assigns |> Map.get(:job) |> is_nil())
    |> assign_defaults()
    |> ok()
  end

  defp assign_defaults(
         %{assigns: %{current_user: %{organization: organization}, currency: currency}} = socket
       ) do
    socket
    |> assign_new(:show_on_public_profile, fn -> false end)
    |> assign_new(:package, fn -> %Package{shoot_count: 1, contract: nil, currency: currency} end)
    |> then(fn %{assigns: %{package: %{currency: currency}}} = socket ->
      socket
      |> assign(:currency, currency)
      |> assign(:currency_symbol, symbol!(currency))
    end)
    |> assign_new(:package_pricing, fn -> %PackagePricing{} end)
    |> assign_new(:contract_changeset, fn -> %{} end)
    |> assign_new(:collapsed_documents, fn -> [0, 1] end)
    |> assign(job_types: Profiles.enabled_job_types(organization.organization_job_types))
    |> assign(global_settings: GlobalSettings.get(organization.id))
    |> choose_initial_step()
    |> assign(default: %{})
    |> assign(custom: false)
    |> assign(job_type: nil)
    |> assign(custom_schedule_type: nil)
    |> assign(active_tab: :contract)
    |> assign(tabs: tabs_list())
    |> assign(default_payment_changeset: nil)
    |> assign(:show_print_credits, false)
    |> assign(:show_discounts, false)
    |> assign(:show_digitals, "close")
    |> assign_changeset(%{})
    |> assign_questionnaires()
  end

  defp assign_payments_changeset(
         %{assigns: %{default_payment_changeset: default_payment_changeset}} = socket,
         params,
         action
       ) do
    changeset =
      params |> CustomPayments.changeset(default_payment_changeset) |> Map.put(:action, action)

    assign(socket, payments_changeset: changeset)
  end

  defp choose_initial_step(%{assigns: %{is_template: true}} = socket) do
    socket
    |> assign(templates: [], step: :details, steps: [:details, :documents, :pricing, :payment])
  end

  defp choose_initial_step(%{assigns: %{current_user: user, job: job, package: package}} = socket) do
    with %{type: job_type} <- job,
         %{id: nil} <- package,
         templates when templates != [] <- Packages.templates_for_user(user, job_type) do
      socket
      |> assign(
        templates: templates,
        step: :choose_template,
        steps: [:choose_template, :details, :pricing, :payment]
      )
    else
      _ -> socket |> assign(templates: [], step: :details, steps: [:details, :pricing, :payment])
    end
  end

  defp choose_initial_step(
         %{assigns: %{current_user: user, booking_event: booking_event, package: package}} =
           socket
       ) do
    with nil <- booking_event.package_template,
         templates when templates != [] <- Packages.templates_with_single_shoot(user) do
      socket
      |> assign(
        templates: templates,
        step: :choose_template,
        steps: [:choose_template, :details, :documents, :pricing, :payment]
      )
    else
      _ ->
        socket
        |> assign(
          templates: [],
          package: booking_event.package_template || package,
          step: :details,
          steps: [:details, :documents, :pricing, :payment]
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal">
      <.close_x />

      <.steps step={@step} steps={@steps} target={@myself} />
      <.step_heading name={@step} is_edit={@package.id} />

      <.form for={@changeset} :let={f} phx-change="validate" phx-submit="submit" phx-target={@myself} id={"form-#{@step}"}>
        <input type="hidden" name="step" value={@step} />

        <.wizard_state form={f} contract_changeset={@contract_changeset} />

        <.step name={@step} f={f} {assigns} />

        <.footer class="pt-10">
          <.step_buttons name={@step} form={f} is_valid={step_valid?(assigns)} myself={@myself} />

          <button class="btn-secondary" title="cancel" type="button" phx-click="modal" phx-value-action="close">
            Cancel
          </button>
        </.footer>
      </.form>
    </div>
    """
  end

  defp step_valid?(%{step: :payment, payments_changeset: payments_changeset}) do
    remaining_price = Changeset.get_field(payments_changeset, :remaining_price)
    Money.zero?(remaining_price) || payments_changeset.valid?
  end

  defp step_valid?(%{step: :documents, contract_changeset: contract}), do: contract.valid?

  defp step_valid?(assigns),
    do:
      Enum.all?(
        [
          assigns.download_changeset,
          assigns.package_pricing,
          assigns.multiplier,
          assigns.changeset
        ],
        & &1.valid?
      )

  def wizard_state(assigns) do
    assigns = assign(assigns, fields: @all_fields)

    ~H"""
      <%= for field <- @fields, input_value(@form, field) do %>
        <%= hidden_input @form, field, id: nil %>
      <% end %>

      <% c = to_form(@contract_changeset) %>
      <%= for field <- [:name, :content, :contract_template_id, :edited], input_value(c, field) do %>
        <%= hidden_input c, field, id: nil %>
      <% end %>
    """
  end

  def step_heading(%{name: :choose_template} = assigns) do
    ~H"""
      <h1 class="mt-2 mb-4 text-3xl font-bold">Package Templates</h1>
    """
  end

  def step_heading(assigns) do
    ~H"""
      <h1 class="mt-2 mb-4 text-3xl"><strong class="font-bold"><%= heading_title(@is_edit) %>:</strong> <%= heading_subtitle(@name) %></h1>
    """
  end

  def heading_title(is_edit), do: if(is_edit, do: "Edit Package", else: "Add a Package")

  def heading_subtitle(step) do
    Map.get(
      %{
        details: "Provide Details",
        documents: "Select Documents",
        pricing: "Set Pricing",
        payment: "Set Payment Schedule"
      },
      step
    )
  end

  def step_subheading(%{name: :choose_template} = assigns) do
    ~H"""
    """
  end

  def step_subheading(assigns) do
    ~H"""
      <p>Create a new package</p>
    """
  end

  def step_buttons(%{name: :choose_template} = assigns) do
    ~H"""
    <button class="btn-primary" title="Use template" type="submit" phx-disable-with="Use Template" disabled={!template_selected?(@form)}>
      Use template
    </button>

    <%= if template_selected?(@form) do %>
      <button class="btn-primary" title="Customize" type="button" phx-click="customize-template" phx-target={@myself}>
        Customize
      </button>
    <% else %>
      <button class="btn-primary" title="New Package" type="button" phx-click="new-package" phx-target={@myself}>
        New Package
      </button>
    <% end %>
    """
  end

  def step_buttons(%{name: step} = assigns) when step in [:details, :documents, :pricing] do
    ~H"""
    <button class="btn-primary" title="Next" type="submit" disabled={!@is_valid} phx-disable-with="Next">
      Next
    </button>
    """
  end

  def step_buttons(%{name: :payment} = assigns) do
    ~H"""
    <button class="px-8 mb-2 sm:mb-0 btn-primary" title="Save" type="submit" disabled={!@is_valid} phx-disable-with="Save">
      Save
    </button>
    """
  end

  def step(%{name: :choose_template} = assigns) do
    ~H"""
    <.packages_search_component id="packages" target={@myself} module={TodoplaceWeb.PackageLive.PackagesSearchComponent} job_types={@job_types} current_user={@current_user} />
    <h1 class="mt-6 text-xl font-bold">Select Package <%= if template_selected?(@f), do: "(1 selected)", else: "" %></h1>
    <div class="hidden sm:flex items-center justify-between border-b-8 border-blue-planning-300 font-semibold text-lg pb-3 mt-4 text-base-250">
      <%= for title <- ["Package name", "Package pricing", "Select package"] do %>
        <div class="w-1/3 last:text-center"><%= title %></div>
      <% end %>
    </div>
    <%= if @templates == [] do %>
        <div class="p-6 text-center text-base-300 w-full">
        No packages found using that search criteria
        </div>
    <% else %>
      <%= for template <- @templates do %>
        <% checked = is_checked(input_value(@f, :package_template_id), template) %>
        <.package_row package={template} checked={checked}>
          <input class={classes("w-5 h-5 mr-2.5   radio", %{"checked" => checked})} type="radio" name={input_name(@f, :package_template_id)} value={template.id} />
        </.package_row>
      <% end %>
    <% end %>
    """
  end

  def step(%{name: :details} = assigns) do
    job = Map.get(assigns, :job)

    assigns =
      Enum.into(assigns, %{
        placeholder_job_type:
          if !assigns.is_template && job do
            job.type
          else
            job_type = Map.get(assigns.package, :job_type)
            if(job_type, do: job_type, else: "wedding")
          end,
        is_booking_event: !Map.get(assigns.package, :id)
      })

    ~H"""
      <%= if !@is_template && Map.get(assigns, :job) do %>
      <div class="rounded bg-gray-100 p-4">
        <h6 class="rounded uppercase bg-blue-planning-300 text-white px-2 py-0.5 text-sm font-semibold mb-1 inline-block">Note</h6>
        <p class="text-base-250">If you don't see any of your packages to select from, you likely selected the wrong photography type when creating the lead. Your package needs to match the lead photography type.</p>
      </div>
      <% end %>

      <.package_basic_fields form={@f} job_type={@placeholder_job_type} />

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 md:gap-8 mt-4">
        <div>
          <.input_label form={@f} class="flex items-end justify-between mb-3 text-sm font-semibold" field={:thumbnail_url}
          >
            <span>Package Thumbnail <%= error_tag(@f, :thumbnail_url) %></span>
          </.input_label>
          <.image_upload_input
            current_user={@current_user}
            upload_folder="package_image"
            name={input_name(@f, :thumbnail_url)}
            url={input_value(@f, :thumbnail_url)}
          >
            <:image_slot>
              <.blurred_thumbnail class="h-full w-full" url={input_value(@f, :thumbnail_url)} />
            </:image_slot>
          </.image_upload_input>
        </div>
        <div class="flex flex-col">
          <.input_label form={@f} class="flex items-start justify-between mb-3 text-sm font-semibold" field={:description}>
            <span>Description <%= error_tag(@f, :description) %></span>
            <button type="button" phx-hook="ClearQuillInput" id="clear-description" data-input-name={input_name(@f,:description)} class="text-red-sales-300 underline">
              Clear
            </button>
          </.input_label>
          <div class="flex-grow">
            <.quill_input f={@f} html_field={:description} editor_class="min-h-[16rem]" class="flex flex-col h-full" placeholder={"Description of your#{@placeholder_job_type} offering and pricing "} />
          </div>
        </div>
      </div>

      <%= if @is_template || @is_booking_event do %>
        <hr class="mt-6" />

        <div class="flex flex-col mt-6">
          <div>
            <.input_label form={@f} class="mb-1 text-sm font-semibold" field={:job_type}>
              Select a Photography Type
            </.input_label>
            <.tooltip class="" content="You can enable more photography types in your <a class='underline' href='/package_templates?edit_photography_types=true'>package settings</a>." id="photography-type-tooltip">
              <.link navigate="/package_templates?edit_photography_types=true">
                <span class="link text-sm">Not seeing your photography type?</span>
              </.link>
            </.tooltip>
          </div>

          <div class="grid grid-cols-2 gap-3 mt-2 sm:grid-cols-4 sm:gap-5">
            <%= for job_type <- @job_types do %>
              <.job_type_option type="radio" name={input_name(@f, :job_type)} job_type={job_type} checked={input_value(@f, :job_type) == job_type} />
            <% end %>
          </div>

          <%= unless @is_booking_event do %>
            <div class="col-start-7">
              <label class="flex items-center mt-8">
                <%= checkbox @f, :show_on_public_profile, class: "w-6 h-6 checkbox" %>
                <h1 class="text-xl ml-2 mr-1 font-bold">Show package on my Public Profile</h1>
              </label>
              <p class="ml-8 text-gray-500"> Keep this package hidden from potential clients until you're ready to showcase it</p>
            </div>
          <% end %>
        </div>
      <% end %>
    """
  end

  def step(%{name: :documents} = assigns) do
    ~H"""
    <div class="font-normal text-base-250 w-fit">
      As with most things in Todoplace, we have created default contracts/questionnaires for you to use. If you’d like to make your own, check out global questionnaire and contract management. <strong>NOTE: Make sure to save your work and come back to this page to select your custom documents.</strong>
    </div>

    <div class="flex flex-row gap-4 mt-2 mb-8">
      <a class="items-center text-blue-planning-300 underline font-normal flex gap-2" target="_blank" href={~p"/contracts"}>
        Manage contracts <.icon name="external-link" class="w-3.5 h-3.5"/>
      </a>
      <a class="items-center text-blue-planning-300 underline font-normal flex gap-2" target="_blank" href={~p"/questionnaires"}>
        Manage questionnaires <.icon name="external-link" class="w-3.5 h-3.5"/>
      </a>
    </div>

    <div class="flex flex-row text-blue-planning-300 mb-4">
      <%= for %{name: name, concise_name: concise_name} <- @tabs do %>
        <div class={classes("flex px-3 font-bold rounded-lg whitespace-nowrap text-lg", %{"bg-blue-planning-100 text-base-300" => Atom.to_string(@active_tab) == concise_name})}>
          <button type="button" phx-click={"toggle-tab"} phx-value-active={concise_name} phx-target={@myself} ><%= name %></button>
        </div>
      <% end %>
    </div>

    <span class="hidden sm:flex items-center justify-between border-b-4 border-blue-planning-300 font-semibold text-lg text-base-250" />
    <section {testid("document-contracts")} class="border border-base-200 rounded-lg mt-6 overflow-hidden">
      <div class={classes(%{"hidden" => !(@active_tab == :contract)})}>
        <% c = to_form(@contract_changeset) %>
          <div class="hidden sm:flex items-center justify-between table-auto font-semibold text-lg p-3 rounded-t-lg bg-base-200">
            <div class="w-1/3">Contract name</div>
            <div class="w-1/3 text-center">Job type</div>
            <div class="w-1/3 text-center">Select contract</div>
          </div>
          <%= for contract <- @contract_options do %>
            <div {testid("contracts-row")} class="md:mx-3 md:px-0 px-3 mx-0 border py-3 sm:py-4 md:border-none border-b md:rounded-lg rounded-none">
              <label class="flex items-center justify-between cursor-pointer">
                <h3 class="font-xl font-bold w-1/3"><%= contract.name %></h3>
                <p class="w-1/3 text-center"><%= contract.job_type %></p>
                <div class="w-1/3 text-center">
                  <%= radio_button(c, :contract_template_id, contract.id, class: "w-5 h-5 mr-2.5 radio cursor-pointer") %>
                </div>
              </label>
            </div>
          <% end %>
      </div>
      <div class={classes(%{"hidden" => !(@active_tab == :question)})}>
        <%= if Enum.empty?(@questionnaires) do %>
          <p>Looks like you don't have any questionnaires. Please add one first <.live_link to={~p"/questionnaires"} class="underline text-blue-planning-300">here</.live_link>. (You're modal will close and you'll have to come back)</p>
        <% else %>
          <div class="hidden sm:flex items-center justify-between table-auto font-semibold text-lg p-3 rounded-t-lg bg-base-200">
            <div class="w-1/3">Questionnaire name</div>
            <div class="w-1/3 text-center">Job type</div>
            <div class="w-1/3 text-center">Select questionnaire</div>
          </div>
          <%= for questionnaire <- @questionnaires do %>
            <div class="md:mx-3 md:px-0 px-3 mx-0 border py-3 sm:py-4 md:border-none border-b md:rounded-lg rounded-none">
              <label class="flex items-center justify-between cursor-pointer">
                <h3 class="font-xl font-bold w-1/3"><%= questionnaire.name %></h3>
                <p class="w-1/3 text-center"><%= questionnaire.job_type %></p>
                <div class="w-1/3 text-center">
                  <%= radio_button(@f, :questionnaire_template_id, questionnaire.id, class: "w-5 h-5 mr-2.5 radio cursor-pointer") %>
                </div>
              </label>
            </div>
          <% end %>
        <% end %>
      </div>
    </section>
    """
  end

  def step(%{name: :pricing} = assigns) do
    ~H"""
      <div class="">
        <div class="flex flex-row text-base-250 font-bold">
          <div class="flex w-4/5">Item</div>
          <div class="flex w-1/5">Total</div>
        </div>
        <div class="border-blue-planning-300 border-2 mt-4"></div>

        <div class="flex mt-6">
          <div class="flex flex-col w-4/5 items-center md:items-start">
            <label class="mb-3" for={input_id(@f, :base_price)}>
              <h2 class="mb-1 text-xl font-bold">Creative Session Fee</h2>
              <span class="text-base-250">Input your base session fee; if your location charges taxes, we’ll calculate those for your client at checkout.</span>
            </label>

            <div class="flex flex-row items-center w-auto mt-6 border rounded-lg">
              <%= input @f, :base_price, placeholder: "#{@currency_symbol}0.00", class: "sm:w-32 w-full bg-white px-1 border-none text-lg sm:mt-0 font-normal text-center", phx_hook: "PriceMask", data_currency: @currency_symbol %>
            </div>
            <%= text_input @f, :currency, value: @currency, class: "form-control border-none text-base-250", phx_debounce: "500", maxlength: 3, autocomplete: "off", readonly: true %>
          </div>
          <b class="flex w-1/5"> <%= current(@f) |> Map.get(:base_price) %> </b>
        </div>

        <hr class="w-full mt-6"/>
        <%= if @currency in products_currency() do %>
          <.package_print_credit_fields f={@f} package_pricing={@package_pricing} target={@myself} show_print_credits={@show_print_credits} currency_symbol={@currency_symbol} currency={@currency}/>

          <hr class="w-full mt-6"/>
        <% end %>

        <.digital_download_fields package_form={@f} download_changeset={@download_changeset} package_pricing={@package_pricing} target={@myself} show_digitals={@show_digitals} currency_symbol={@currency_symbol} currency={@currency}/>

        <hr class="w-full mt-6"/>
        <% changeset = current(@f) %>
        <% multiplier = current(@multiplier) %>
        <% print_credits_include_in_total = Map.get(changeset, :print_credits_include_in_total) %>
        <% digitals_include_in_total = Map.get(changeset, :digitals_include_in_total) %>

        <div class="flex md:flex-row flex-col">
          <div class="flex flex-col w-full md:w-2/3">
            <div class="mt-9 md:mt-1">
              <h2 class="mb-2 text-xl font-bold justify-self-start sm:mr-4 whitespace-nowrap">Package Total</h2>
              <p class="text-base-250 mb-2">Taxes will be calculated at checkout for your client.</p>
            </div>
            <button {testid("add-discount-surcharge")} class={classes("underline text-blue-planning-300 inline-block w-max", %{"hidden" => @show_discounts})} type="button" phx-target={@myself} phx-click="edit-discounts">Add a discount or surcharge</button>

            <div class={classes("border border-solid mt-6 rounded-lg md:w-3/4 w-full", %{"hidden" => !@show_discounts})}>
              <div class="p-2 font-bold bg-base-200 flex flex-row">
                Discount or Surcharge Settings
                <a phx-target={@myself} phx-click="edit-discounts" class="flex items-center cursor-pointer ml-auto"><.icon name="close-x" class="w-3 h-3 stroke-current stroke-2"/></a>
              </div>
              <% m = to_form(@multiplier) %>

              <div class="mt-4 px-6 pb-6">
                <label class="flex sm:mt-8 justify-self-start font-bold">
                  <%= checkbox(m, :is_enabled, class: "w-5 h-5 mr-2 mt-1 checkbox") %>
                  <div class="flex flex-col">
                    Apply a discount or surcharge
                    <span class="font-normal text-sm text-base-250">Please select all the options to which the discount should be applied</span>
                  </div>
                </label>

                <%= if m |> current() |> Map.get(:is_enabled) do %>
                  <div class="flex flex-col items-center pl-0 my-6 sm:flex-row sm:pl-16">
                    <h2 class="self-start mt-3 text-base-250 sm:self-auto sm:mt-0 justify-self-start sm:mr-4 whitespace-nowrap">Apply a</h2>

                    <div class="flex w-full mt-3 sm:mt-0 gap-2 items-center">
                      <%= input m, :percent, placeholder: "0.00%", value: "#{input_value(m, :percent)}", class: "w-24 text-center p-3 border rounded-lg border-blue-planning-300", phx_hook: "PercentMask", data_include: false, data_include_sign: "false" %>
                      <p>%</p>
                      <%= select_field(m, :sign, Multiplier.sign_options(), class: "text-left flex-grow sm:flex-grow-0 px-4 py-4 pr-10") %>
                    </div>
                  </div>

                  <div class="flex items-center pl-0 sm:flex-row sm:pl-16">
                    <%= checkbox m, :discount_base_price, class: "w-5 h-5 mr-2.5 checkbox" %>
                    <%= label_for m, :discount_base_price, label: "Apply to creative session", class: "font-normal" %>
                  </div>
                  <%= if @currency in products_currency() do%>
                    <div class={classes("flex items-center pl-0 sm:flex-row sm:pl-16", %{"text-base-250 cursor-none" => !print_credits_include_in_total})}>
                      <%= checkbox m, :discount_print_credits, class: "w-5 h-5 mr-2.5 checkbox", disabled: !print_credits_include_in_total %>
                      <%= label_for m, :discount_print_credits, label: "Apply to print credit", class: "font-normal" %>
                      <.tooltip class="ml-1" content="<strong>To apply a print credit discount/surcharge</strong>: you need to add an amount to your print credits and check “Include in package total calculation”" id="include-print" />
                    </div>
                  <% end %>
                  <div class={classes("flex items-center pl-0 sm:flex-row sm:pl-16", %{"text-base-250 cursor-none" => !digitals_include_in_total})}>
                    <%= checkbox m, :discount_digitals, class: "w-5 h-5 mr-2.5 checkbox", disabled: !digitals_include_in_total %>
                    <%= label_for m, :discount_digitals, label: "Apply to digitals", class: "font-normal" %>
                    <.tooltip class="ml-1" content="<strong>To apply a digital collection discount/surcharge</strong>: select “Clients don’t have to pay for some Digital Images”, add some images you want to provide them, and check “Include in package total calculation”" id="include-digital" />
                  </div>
                <% end %>
              </div>
            </div>

          </div>
          <div {testid("sumup-grid")} class="grid w-full md:w-1/3 h-fit">
            <.show_discounts>
              <span class="flex w-2/3 mt-4 font-bold">Creative Session Fee</span>
              <span class="flex w-1/3 mt-4 justify-end mr-5">+<%= Map.get(changeset, :base_price) %></span>
            </.show_discounts>
            <%= if Map.get(multiplier, :discount_base_price) do %>
              <.show_discounts>
              <span class="flex w-2/3 text-base-250"><%= get_discount_text(multiplier) %></span>
              <span class="flex w-1/3 text-base-250 justify-end mr-5"><%= base_adjustment(@f) %></span>
              </.show_discounts>
            <% end %>
            <%= if print_credits_include_in_total do %>
              <.show_discounts>
                <span class="flex w-2/3 mt-2 font-bold">Professional Print Credit</span>
                <span class="flex w-1/3 mt-2 justify-end mr-5">+<%= Map.get(changeset, :print_credits) %></span>
              </.show_discounts>
            <% end %>
            <%= if Map.get(multiplier, :discount_print_credits) do %>
              <.show_discounts>
                <span class="flex w-2/3 text-base-250"><%= get_discount_text(multiplier) %></span>
                <span class="flex w-1/3 text-base-250 justify-end mr-5"><%= print_cridets_adjustment(@f) %></span>
              </.show_discounts>
            <% end %>
            <%= if digitals_include_in_total do %>
            <.show_discounts>
                <span class="flex w-2/3 mt-2 font-bold">Digital Collection</span>
                <span class="flex w-1/3 mt-2 justify-end mr-5">+<%= digitals_total(@download_changeset) %></span>
              </.show_discounts>
            <% end %>
            <%= if Map.get(multiplier, :discount_digitals) do %>
              <.show_discounts>
                <span class="flex w-2/3 text-base-250"><%= get_discount_text(multiplier) %></span>
                <span class="flex w-1/3 text-base-250 justify-end mr-5"><%= digitals_adjustment(@f) %></span>
              </.show_discounts>
            <% end %>
            <.show_discounts>
              <div class="flex flex-row gap-4 p-2 mt-4 w-full bg-base-200 rounded-lg mb-2 mt-4 text-xl font-bold justify-self-start whitespace-nowrap">
                <span class="flex w-2/3 font-bold">Package Total</span>
                <span class="flex w-1/3 font-bold justify-end mr-3"><%= total_price(@f) %></span>
              </div>
            </.show_discounts>
          </div>
        </div>

      <hr class="w-full mt-6"/>
      </div>
    """
  end

  def step(
        %{
          name: :payment,
          f: %{params: params},
          default_payment_changeset: _
        } = assigns
      ) do
    job = Map.get(assigns, :job)

    job_type =
      Map.get(params, "job_type") ||
        if(job, do: job.type, else: Map.get(assigns.package, :job_type))

    assigns = assign(assigns, job_type: job_type) |> Enum.into(%{job: job})

    ~H"""
    <div>
      <div class="flex flex-col items-start justify-between w-full sm:items-center sm:flex-row sm:w-auto">
        <div class="mb-2">
          <h2 class="mb-1 text-xl font-bold">Payment Schedule Preset</h2>
          Use your default payment schedule or select a new one. Any changes made will result in a custom payment schedule.
        </div>
      </div>
      <% pc = to_form(@payments_changeset) %>
      <div {testid("select-preset-type")} class="grid gap-6 md:grid-cols-2 grid-cols-1 mt-8">
        <%= select pc, :schedule_type, payment_dropdown_options(@job_type, input_value(pc, :schedule_type)), wrapper_class: "mt-4", class: "py-3 border rounded-lg border-base-200 cursor-pointer", phx_update: "update" %>
        <div {testid("preset-summary")} class="flex items-center"><%= get_tags(pc, @currency) %></div>
      </div>
      <hr class="w-full my-6 md:my-8"/>
      <div class="flex flex-col items-start justify-between w-full sm:items-center sm:flex-row sm:w-auto">
        <div class="mb-2">
          <h2 class="mb-1 text-xl font-bold">Payment Schedule Details</h2>
          Note: payment schedules are limited to up to 12 payments for any package but you can enable additional “Buy Now, Pay Later” payment methods via Stripe in your Todoplace Account Finance settings for additional client flexibility.
        </div>
      </div>
      <div class="flex flex-col items-start w-full sm:items-center sm:flex-row sm:w-auto">
        <div class="mb-8">
          <h2 class="mb-1 font-bold">Payment By:</h2>
          <div class="flex flex-col">
            <label class="my-2"><%= radio_button(pc, :fixed, true, class: "w-5 h-5 mr-2 radio cursor-pointer") %>Fixed amount</label>
            <label><%= radio_button(pc, :fixed, false, class: "w-5 h-5 mr-2 radio cursor-pointer") %>Percentage</label>
          </div>
        </div>
      </div>
      <div class="flex mb-6 md:w-1/2">
        <h2 class="font-bold">Balance to collect:</h2>
        <div {testid("balance-to-collect")} class="ml-auto"><%= total_price(@f) %> <%= unless input_value(pc, :fixed), do: "(100%)" %></div>
      </div>
      <%= hidden_input pc, :total_price %>
      <%= hidden_input pc, :remaining_price %>
      <%= inputs_for pc, :payment_schedules, fn p -> %>
        <%= hidden_input p, :shoot_date %>
        <%= hidden_input p, :last_shoot_date %>
        <%= hidden_input p, :schedule_date %>
        <%= hidden_input p, :description, value: get_tag(p, input_value(pc, :fixed), @currency) %>
        <%= hidden_input p, :payment_field_index, value: p.index %>
        <%= hidden_input p, :fields_count, value: length(input_value(pc, :payment_schedules)) %>
        <div {testid("payment-count-card")} class="border rounded-lg border-base-200 md:w-1/2 pb-2 mt-3">
          <div class="flex items-center bg-base-200 px-2 p-2">
            <div class="mb-2 text-xl font-bold">Payment <%= p.index + 1 %></div>
              <%= if p.index != 0 do %>
                <.icon_button class="ml-auto" title="remove" phx-value-index={p.index} phx-click="remove-payment" phx-target={@myself} color="red-sales-300" icon="trash">
                  Remove
                </.icon_button>
              <% end %>
          </div>
          <h2 class="my-2 px-2 font-bold">Payment Due</h2>
          <div class="flex flex-col w-full px-2">
            <label class="items-center font-medium">
              <div class={classes("flex items-center", %{"mb-2" => is_nil(@job)})}>
                <%= radio_button(p, :interval, true, class: "w-5 h-5 mr-4 radio cursor-pointer") %>
                <span class="font-medium">At the following interval</span>
              </div>
            </label>
            <div class={classes("flex my-1 ml-8 items-center text-base-250", %{"hidden" => is_nil(@job)})}>
              <.icon name="calendar" class="w-4 h-4 mr-1 text-base-250"/>
              <%= if input_value(p, :shoot_date) |> is_value_set(), do: input_value(p, :schedule_date) |> Calendar.strftime("%m-%d-%Y"), else: "Add shoot to generate date" %>
            </div>
            <div {testid("due-interval")} class={classes("flex flex-col my-2 ml-8", %{"hidden" => !input_value(p, :interval)})}>
              <%= select p, :due_interval, interval_dropdown_options(input_value(p, :due_interval), p.index), wrapper_class: "mt-4", class: "w-full py-3 border rounded-lg border-base-200", phx_update: "update" %>
              <%= if message = p.errors[:schedule_date] do %>
                <div class="flex py-1 w-full text-red-sales-300 text-sm"><%= translate_error(message) %></div>
              <% end %>
            </div>
            <label>
              <div class={classes("flex items-center", %{"mb-2" => input_value(p, :interval)})}>
                <%= radio_button(p, :interval, false, class: "w-5 h-5 mr-4 radio cursor-pointer") %>
                <span class="font-medium">At a custom time</span>
              </div>
            </label>
            <%= unless input_value(p, :interval) do %>
              <%= if input_value(p, :due_at) || (input_value(p, :shoot_date) |> is_value_set()) do %>
                <div class="flex flex-col my-2 ml-8 cursor-pointer">
                  <.date_picker_field class="w-full px-4 text-lg cursor-pointer" id={"payment-interval-#{p.index}"} form={p} field={:due_at} input_placeholder="mm/dd/yyyy" input_label="Payment Date" data_min_data={Date.utc_today()} />
                  <%= if message = p.errors[:schedule_date] do %>
                    <div class="flex py-1 w-full text-red-sales-300 text-sm"><%= translate_error(message) %></div>
                  <% end %>
                </div>
              <% else %>
                <div class="flex flex-col ml-8">
                  <div class="flex w-full my-2">
                    <div class="w-2/12">
                      <%= select p, :count_interval, 1..10, wrapper_class: "mt-4", class: "w-full py-3 border rounded-lg border-base-200", phx_update: "update" %>
                    </div>
                      <div class="ml-2 w-2/5">
                      <%= select p, :time_interval, ["Day", "Month", "Year"], wrapper_class: "mt-4", class: "w-full py-3 border rounded-lg border-base-200", phx_update: "update" %>
                    </div>
                    <div class="ml-2 w-2/3">
                      <%= select p, :shoot_interval, ["Before 1st Shoot", "Before Last Shoot"], wrapper_class: "mt-4", class: "w-full py-3 border rounded-lg border-base-200", phx_update: "update" %>
                    </div>
                  </div>
                  <%= if message = p.errors[:schedule_date] do %>
                    <div class="flex py-1 w-full text-red-sales-300 text-sm"><%= translate_error(message) %></div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
            <div class="flex my-2">
              <div class="flex flex-col ml-auto">
                <div class="flex flex-row items-center w-auto mt-6 border rounded-lg relative border-blue-planning-300">
                  <%= input p, :price, placeholder: "#{@currency_symbol}0.00", class: classes("w-32 bg-white p-3 border-none text-lg sm:mt-0 font-normal text-center", %{"hidden" => !input_value(pc, :fixed)}), phx_hook: "PriceMask", data_currency: @currency_symbol %>
                </div>
                <%= text_input p, :currency, value: @currency, class: classes("w-32 form-control text-base-250 border-none", %{"hidden" => !input_value(pc, :fixed)}), phx_debounce: "500", maxlength: 3, autocomplete: "off" %>
              </div>
              <%= input p, :percentage, placeholder: "0.00%", value: "#{input_value(p, :percentage)}%", class: classes("w-24 text-center p-3 border rounded-lg border-blue-planning-300 ml-auto", %{"hidden" => input_value(pc, :fixed)}), phx_hook: "PercentMask" %>
            </div>
          </div>
        </div>
      <% end %>

      <.icon_button phx-click="add-payment" phx-target={@myself} class={classes("text-sm bg-white py-1.5 shadow-lg mt-5", %{"hidden" => hide_add_button(pc)})} color="blue-planning-300" icon="plus">
        Add another payment
      </.icon_button>

      <div class="flex mb-2 md:w-1/2 mt-5">
        <h2 class="font-bold">Remaining to collect:</h2>
        <div {testid("remaining-to-collect")} class="ml-auto">
          <%= case input_value(pc, :remaining_price) do %>
            <% value -> %>
            <%= if Money.zero?(value) do %>
              <span class="text-green-finances-300"><%= get_remaining_price(input_value(pc, :fixed), value, total_price(@f)) %></span>
            <% else %>
              <span class="text-red-sales-300"><%= get_remaining_price(input_value(pc, :fixed), value, total_price(@f)) %></span>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event(
        "toggle-collapsed-documents",
        %{"index" => index},
        %{assigns: %{collapsed_documents: collapsed_documents}} = socket
      ) do
    index = String.to_integer(index)

    collapsed_documents =
      if Enum.member?(collapsed_documents, index) do
        Enum.filter(collapsed_documents, &(&1 != index))
      else
        collapsed_documents ++ [index]
      end

    socket
    |> assign(:collapsed_documents, collapsed_documents)
    |> noreply()
  end

  def handle_event("toggle-tab", %{"active" => active_tab}, socket) do
    socket
    |> assign(:active_tab, String.to_atom(active_tab))
    |> noreply()
  end

  @impl true
  def handle_event(
        "back",
        %{},
        %{assigns: %{step: step, steps: steps}} = socket
      ) do
    previous_step = Enum.at(steps, Enum.find_index(steps, &(&1 == step)) - 1)

    changeset = update_changeset(socket, step: previous_step)

    socket
    |> assign(step: previous_step, changeset: changeset)
    |> noreply()
  end

  @impl true
  def handle_event(
        "remove-payment",
        %{"index" => index},
        %{assigns: %{payments_changeset: payments_changeset}} = socket
      ) do
    params = payments_changeset |> current() |> map_keys()

    payment_schedules =
      params
      |> Map.get("payment_schedules")
      |> List.delete_at(String.to_integer(index))
      |> map_keys()
      |> Enum.with_index(fn %{"payment_field_index" => field_index} = payment, count ->
        Map.put(payment, "payment_field_index", if(field_index, do: field_index, else: count))
      end)

    params = Map.merge(params, %{"payment_schedules" => payment_schedules})

    socket
    |> assign_payments_changeset(params, :validate)
    |> noreply()
  end

  @impl true
  def handle_event(
        "add-payment",
        %{},
        %{assigns: %{payments_changeset: payments_changeset} = assigns} = socket
      ) do
    job = Map.get(assigns, :job, %{id: nil})
    params = payments_changeset |> current() |> map_keys()

    payment_schedules =
      params
      |> Map.get("payment_schedules")
      |> map_keys()
      |> Enum.with_index(fn %{"payment_field_index" => field_index} = payment, count ->
        Map.put(payment, "payment_field_index", if(field_index, do: field_index, else: count))
      end)

    new_payment =
      if params["fixed"] do
        %{"price" => nil, "due_interval" => "Day Before Shoot"}
      else
        %{"percentage" => 8, "due_interval" => "8% Day Before"}
      end
      |> Map.merge(%{
        "shoot_date" => get_first_shoot(job),
        "last_shoot_date" => get_last_shoot(job),
        "interval" => true,
        "payment_field_index" => length(payment_schedules)
      })

    params =
      Map.merge(params, %{
        "payment_schedules" =>
          payment_schedules ++ [Map.merge(payment_schedules |> List.first(), new_payment)]
      })

    socket
    |> assign_payments_changeset(params, :validate)
    |> noreply()
  end

  @impl true
  def handle_event("validate", params, %{assigns: %{currency: currency}} = socket)
      when not is_map_key(params, "parsed?") do
    __MODULE__.handle_event(
      "validate",
      params
      |> Currency.parse_params_for_currency({Money.Currency.symbol(currency), currency})
      |> put_in(["package", "name"], get_in(params, ["package", "name"])),
      socket
    )
  end

  @impl true
  def handle_event(
        "validate",
        %{"step" => "payment", "custom_payments" => params},
        %{assigns: %{payments_changeset: payments_changeset}} = socket
      ) do
    custom_payments_changeset =
      %CustomPayments{} |> Changeset.cast(params, [:fixed, :schedule_type])

    schedule_type = Changeset.get_field(custom_payments_changeset, :schedule_type)
    fixed = Changeset.get_field(custom_payments_changeset, :fixed)
    price = Changeset.get_field(payments_changeset, :total_price)

    cond do
      schedule_type != Changeset.get_field(payments_changeset, :schedule_type) ->
        schedule_type_switch(socket, price, schedule_type)

      fixed != Changeset.get_field(payments_changeset, :fixed) ->
        fixed_switch(socket, fixed, price, params)

      true ->
        socket |> maybe_assign_custom(params)
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{"package" => %{"job_type" => _}, "_target" => ["package", "job_type"]} = params,
        socket
      ) do
    socket
    |> assign_changeset(params |> Map.drop(["contract"]), :validate)
    |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "contract" => %{"contract_template_id" => template_id},
          "_target" => ["contract", "contract_template_id"]
        },
        socket
      ) do
    template_id = template_id |> to_integer()

    socket
    |> assign_contract_changeset(%{"edited" => false, "contract_template_id" => template_id})
    |> noreply()
  end

  # TODO: need to remove this code
  # @impl true
  # def handle_event(
  #       "validate",
  #       %{
  #         "package" => %{"questionnaire_template_id" => id},
  #         "_target" => ["package", "questionnaire_template_id"]
  #       } = params,
  #       socket
  #     ) do
  #   socket
  #   |> assign_changeset(params, :validate)
  #   |> noreply()
  # end

  # @impl true
  # def handle_event("validate", %{"contract" => contract} = params, socket) do
  #   contract = contract |> Map.put_new("edited", Map.get(contract, "quill_source") == "user")

  #   params = params |> Map.put("contract", contract)

  #   socket
  #   |> assign_changeset(params, :validate)
  #   |> assign_contract_changeset(params)
  #   |> noreply()
  # end

  @impl true
  def handle_event("validate", params, socket) do
    socket |> assign_changeset(params, :validate) |> noreply()
  end

  @impl true
  def handle_event("submit", params, %{assigns: %{currency: currency}} = socket)
      when not is_map_key(params, "parsed?") do
    __MODULE__.handle_event(
      "submit",
      params
      |> Currency.parse_params_for_currency({Money.Currency.symbol(currency), currency})
      |> put_in(["package", "name"], get_in(params, ["package", "name"])),
      socket
    )
  end

  @impl true
  def handle_event(
        "submit",
        %{
          "package" => %{"package_template_id" => package_template_id},
          "step" => "choose_template"
        },
        %{assigns: assigns} = socket
      ) do
    package = find_template(socket, package_template_id)

    questionnaire =
      package
      |> Questionnaire.for_package()

    package_payment_schedules =
      package
      |> Repo.preload(:package_payment_schedules, force: true)
      |> Map.get(:package_payment_schedules)

    changeset = changeset_from_template(socket, package_template_id)

    payment_schedules =
      package_payment_schedules
      |> Enum.map(fn schedule ->
        schedule |> Map.from_struct() |> Map.drop([:package_payment_preset_id])
      end)

    default_contract = Contracts.default_contract(package)

    contract_params = %{
      "content" => Contracts.contract_content(default_contract, package, TodoplaceWeb.Helpers),
      "contract_template_id" => default_contract.id,
      "name" => default_contract.name
    }

    opts = %{
      payment_schedules: payment_schedules,
      action: :insert,
      questionnaire: questionnaire,
      contract_params: contract_params
    }

    job = Map.get(assigns, :job)

    if job do
      insert_package_and_update_job(socket, changeset, job, opts)
    else
      insert_package_and_update_booking_event(socket, changeset, assigns.booking_event, opts)
    end
  end

  @impl true
  def handle_event("submit", %{"step" => "details"} = params, socket) do
    case socket |> assign_changeset(params, :validate) do
      %{assigns: %{changeset: %{valid?: true}}} ->
        socket
        |> assign(step: next_step(socket.assigns))
        |> assign_changeset(params)
        |> assign_questionnaires()
        |> assign_contract_changeset(params)
        |> assign_contract_options()

      socket ->
        socket
    end
    |> noreply()
  end

  @impl true
  def handle_event("submit", %{"step" => "documents"} = params, socket) do
    case socket |> assign_changeset(params, :validate) |> assign_contract_changeset(params) do
      %{assigns: %{contract_changeset: %{valid?: true}}} ->
        socket
        |> assign(step: :pricing)
        |> assign_changeset(params)

      socket ->
        socket
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "submit",
        %{"step" => "pricing"} = params,
        %{
          assigns: %{
            package: package,
            current_user: %{organization: organization}
          }
        } = socket
      ) do
    package =
      if package.id,
        do: package |> Repo.preload(:package_payment_schedules, force: true),
        else: package

    socket
    |> assign_changeset(params)
    |> assign_contract_changeset(params)
    |> then(fn %{assigns: %{changeset: changeset} = assigns} = socket ->
      job_type =
        with nil <- Map.get(assigns, :job),
             nil <- Changeset.get_field(changeset, :job_type),
             %{job_type: nil} <- Map.get(assigns, :package),
             job_type <- get_in(params, ["package", "job_type"]) do
          job_type
        else
          %{type: job_type} -> job_type
          %{job_type: job_type} -> job_type
          job_type -> job_type
        end

      package_payment_presets =
        case package do
          %{package_payment_schedules: []} ->
            PackagePayments.get_package_presets(organization.id, job_type)

          %{package_payment_schedules: %Ecto.Association.NotLoaded{}} ->
            PackagePayments.get_package_presets(organization.id, job_type)

          _ ->
            package
        end

      socket
      |> assign(job_type: job_type)
      |> assign_payment_defaults(job_type, package_payment_presets)
    end)
    |> then(fn %{assigns: %{payments_changeset: payments_changeset}} = socket ->
      socket
      |> assign(default_payment_changeset: payments_changeset)
    end)
    |> noreply()
  end

  @impl true
  def handle_event(
        "submit",
        %{
          "step" => "payment",
          "custom_payments" => payment_params
        } = params,
        %{
          assigns:
            %{
              is_template: false,
              package: %Package{id: nil} = package
            } = assigns
        } = socket
      ) do
    questionnaire_template_id =
      if params["package"]["questionnaire_template_id"] do
        String.to_integer(params["package"]["questionnaire_template_id"])
      else
        nil
      end

    # questionnaire =
    #   Questionnaire.for_package(%{
    #     package
    #     | questionnaire_template_id: Map.get(assigns, :questionnaire_template_id)
    #   })

    questionnaire =
      Questionnaire.for_package(%{package | questionnaire_template_id: questionnaire_template_id})

    socket
    |> maybe_assign_custom(payment_params)
    |> then(fn %{assigns: %{changeset: changeset, payments_changeset: payments_changeset}} =
                 socket ->
      payment_schedules =
        payments_changeset
        |> current()
        |> Map.from_struct()
        |> Map.get(:payment_schedules, [])
        |> Enum.map(fn schedule ->
          schedule |> Map.from_struct() |> Map.drop([:package_payment_preset_id])
        end)

      total_price = Changeset.get_field(payments_changeset, :total_price)

      opts = %{
        total_price: total_price,
        payment_schedules: payment_schedules,
        action: :insert,
        questionnaire: questionnaire
      }

      job = Map.get(assigns, :job)
      package_changeset = update_package_changeset(changeset, payments_changeset)

      if job do
        insert_package_and_update_job(socket, package_changeset, job, opts)
      else
        insert_package_and_update_booking_event(
          socket,
          package_changeset,
          assigns.booking_event,
          opts |> Map.put(:contract_params, Map.get(params, "contract"))
        )
      end
    end)
  end

  @impl true
  def handle_event(
        "submit",
        %{"step" => "payment", "custom_payments" => payment_params} = params,
        %{
          assigns: %{
            is_template: true,
            current_user: %{organization: organization},
            job_type: job_type,
            package: %{id: nil}
          }
        } = socket
      ) do
    payment_preset = PackagePayments.get_package_presets(organization.id, job_type)

    socket
    |> maybe_assign_custom(payment_params)
    |> then(fn %{assigns: %{changeset: changeset, payments_changeset: payments_changeset}} =
                 socket ->
      changeset =
        changeset
        |> Changeset.put_change(:is_template, true)

      case Packages.insert_or_update_package(
             update_package_changeset(changeset, payments_changeset),
             Map.get(params, "contract"),
             get_preset_options(payments_changeset, payment_preset)
           ) do
        {:ok, package} -> successfull_save(socket, package)
        _ -> socket |> noreply()
      end
    end)
  end

  @impl true
  def handle_event(
        "submit",
        %{"step" => "payment"} = params,
        %{assigns: %{booking_event: %{id: _}}} = socket
      ) do
    socket |> save_payment(params)
  end

  @impl true
  def handle_event(
        "submit",
        %{"step" => "payment"} = params,
        %{assigns: %{is_template: false, job: %{id: job_id}}} = socket
      ) do
    socket |> save_payment(params, job_id)
  end

  @impl true
  def handle_event(
        "submit",
        %{"step" => "payment"} = params,
        %{assigns: %{is_template: true}} = socket
      ) do
    socket |> save_payment(params)
  end

  @impl true
  def handle_event("submit", _params, socket), do: socket |> noreply()

  @impl true
  def handle_event("new-package", %{}, socket) do
    socket
    |> assign(step: :details, changeset: update_changeset(socket, step: :details))
    |> noreply()
  end

  @impl true
  def handle_event(
        "customize-template",
        %{},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    package = current(changeset)

    template =
      find_template(socket, package.package_template_id)
      |> Repo.preload([:package_payment_schedules, :contract], force: true)

    changeset = changeset_from_template(template)

    socket
    |> assign(
      step: :details,
      package:
        Map.merge(
          socket.assigns.package,
          Map.take(template, [
            :download_each_price,
            :download_count,
            :base_multiplier,
            :buy_all,
            :print_credits,
            :package_payment_schedules,
            :fixed,
            :schedule_type,
            :contract
          ])
        ),
      changeset: changeset
    )
    |> noreply()
  end

  @impl true
  def handle_event(
        "edit-print-credits",
        _,
        %{assigns: %{show_print_credits: show_print_credits}} = socket
      ) do
    socket
    |> assign(:show_print_credits, !show_print_credits)
    |> noreply()
  end

  @impl true
  def handle_event("edit-discounts", _, %{assigns: %{show_discounts: show_discounts}} = socket) do
    socket
    |> assign(:show_discounts, !show_discounts)
    |> noreply()
  end

  @impl true
  def handle_event("edit-digitals", %{"type" => type}, socket) do
    socket
    |> assign(:show_digitals, type)
    |> noreply()
  end

  def package_pricing_params(nil), do: %{"is_enabled" => false}

  def package_pricing_params(package) do
    case Map.get(package, :print_credits) do
      nil ->
        %{"is_enabled" => false}

      %Money{} = value ->
        %{
          "is_enabled" => Money.positive?(value),
          "print_credits_include_in_total" => Map.get(package, :print_credits_include_in_total),
          "print_credits" => value
        }

      _ ->
        %{}
    end
  end

  defp update_package_changeset(changeset, payments_changeset) do
    payments_struct = payments_changeset |> current() |> Map.from_struct()

    changeset
    |> Changeset.put_change(:schedule_type, Map.get(payments_struct, :schedule_type))
    |> Changeset.put_change(:fixed, Map.get(payments_struct, :fixed))
  end

  defp schedule_type_switch(
         %{assigns: %{changeset: changeset} = assigns} = socket,
         price,
         schedule_type
       ) do
    job = Map.get(assigns, :job, %{id: nil})
    fixed = schedule_type == Changeset.get_field(changeset, :job_type)
    default_presets = get_custom_payment_defaults(socket, schedule_type, fixed)

    presets =
      default_presets
      |> Enum.with_index(
        &Map.merge(
          %{
            "interval" => true,
            "shoot_date" => get_first_shoot(job),
            "last_shoot_date" => get_last_shoot(job),
            "percentage" => "",
            "due_interval" => &1
          },
          get_price_or_percentage(price, fixed, length(default_presets), &2)
        )
      )

    price = if fixed, do: price, else: Money.round(price)

    params = %{
      "total_price" => price,
      "remaining_price" => price,
      "payment_schedules" => presets,
      "fixed" => fixed,
      "schedule_type" => schedule_type
    }

    socket
    |> assign(default: map_default(params))
    |> assign(custom: false)
    |> assign_payments_changeset(params, :validate)
  end

  defp get_price(total_price, presets_count, index) do
    remainder = rem(total_price.amount, presets_count) * 100
    amount = if remainder == 0, do: total_price, else: Money.subtract(total_price, remainder)

    if index + 1 == presets_count do
      Money.divide(amount, presets_count) |> List.first() |> Money.add(remainder)
    else
      Money.divide(amount, presets_count) |> List.first()
    end
  end

  defp get_percentage(presets_count, index) do
    remainder = rem(100, presets_count)
    percentage = if remainder == 0, do: 100, else: 100 - remainder

    if index + 1 == presets_count do
      percentage / presets_count + remainder
    else
      percentage / presets_count
    end
    |> Kernel.trunc()
  end

  defp get_price_or_percentage(total_price, fixed, presets_count, index) do
    if fixed do
      %{"price" => get_price(total_price, presets_count, index)}
    else
      %{"percentage" => get_percentage(presets_count, index)}
    end
  end

  defp fixed_switch(socket, fixed, total_price, params) do
    total_price = if fixed, do: total_price, else: Money.round(total_price)

    {presets, _} =
      params
      |> Map.get("payment_schedules")
      |> Map.values()
      |> update_amount(fixed, total_price, socket.assigns.currency)

    params =
      params
      |> Map.merge(%{
        "total_price" => total_price,
        "remaining_price" => total_price,
        "payment_schedules" => presets
      })

    socket
    |> maybe_assign_custom(params)
  end

  defp update_amount(schedules, fixed, total_price, currency) do
    schedules
    |> Enum.reduce({%{}, Money.new(0, currency)}, fn schedule, {schedules, collection} ->
      schedule = Todoplace.PackagePaymentSchedule.prepare_percentage(schedule)

      changeset =
        %Todoplace.PackagePaymentSchedule{}
        |> Changeset.cast(schedule, [:fields_count, :payment_field_index, :price, :percentage])

      index = Changeset.get_field(changeset, :payment_field_index)
      presets_count = Changeset.get_field(changeset, :fields_count)
      price = Changeset.get_field(changeset, :price)
      percentage = Changeset.get_field(changeset, :percentage)

      if fixed do
        updated_price =
          if(price, do: price.amount, else: percentage_to_price(total_price, percentage))
          |> normalize_price(collection, presets_count, index, total_price)
          |> then(&Money.new(&1, currency))

        {Map.merge(schedules, %{
           "#{index}" => %{schedule | "percentage" => nil, "price" => updated_price}
         }), Money.add(updated_price, collection)}
      else
        updated_percentage =
          if(percentage, do: percentage, else: price_to_percentage(total_price, price))
          |> normalize_percentage(collection, presets_count, index)

        {Map.merge(schedules, %{
           "#{index}" => %{schedule | "percentage" => updated_percentage, "price" => nil}
         }), ((is_integer(collection) && collection) || collection.amount) + updated_percentage}
      end
    end)
  end

  defp normalize_price(price, collection, presets_count, index, total_price) do
    if index + 1 == presets_count do
      Kernel.trunc(total_price.amount - collection.amount)
    else
      price
    end
  end

  defp normalize_percentage(percentage, collection, presets_count, index) do
    collection =
      if is_map(collection) do
        Map.get(collection, :amount, 0)
      else
        collection
      end

    if index + 1 == presets_count do
      100 - collection
    else
      percentage
    end
  end

  defp percentage_to_price(_, nil), do: nil

  defp percentage_to_price(total_price, value),
    do: ((total_price.amount / 10_000 * value) |> Kernel.trunc()) * 100

  defp price_to_percentage(_, nil), do: nil

  defp price_to_percentage(_total_price, %{amount: 0}), do: 0

  defp price_to_percentage(total_price, %{amount: amount}),
    do: (amount / total_price.amount * 100) |> Kernel.trunc()

  defp get_default_price(
         schedule,
         x_schedule,
         %{currency: currency} = price,
         %{fixed: true} = params,
         index
       ) do
    params
    |> Map.get(:package_payment_schedules)
    |> Enum.reduce(new_money(currency), &Money.add(&2, new_money(&1.price, currency)))
    |> then(&Money.subtract(price, &1))
    |> then(fn extra_price ->
      Money.add(
        x_schedule |> Map.get("price") |> new_money(currency),
        get_price(extra_price, length(params.package_payment_schedules), index)
      )
    end)
    |> then(&Map.merge(schedule, %{"price" => &1}))
  end

  defp get_default_price(schedule, _x_schedule, _price, _params, _index), do: schedule

  def new_money(price \\ Money.new(0), currency),
    do: Money.new((price && price.amount) || 0, currency)

  defp assign_payment_defaults(
         %{assigns: %{changeset: changeset} = assigns} = socket,
         job_type,
         params
       ) do
    price = total_price(changeset)
    job = Map.get(assigns, :job, %{id: nil})

    params =
      if params && params.package_payment_schedules != [] do
        presets =
          sort_payment_schedules(params.package_payment_schedules)
          |> map_keys()
          |> Enum.with_index(
            &Map.merge(
              &1,
              %{
                "shoot_date" => get_first_shoot(job),
                "last_shoot_date" => get_last_shoot(job)
              }
              |> get_default_price(&1, price, params, &2)
            )
          )

        price = if params.fixed, do: price, else: Money.round(price)

        %{
          "total_price" => price,
          "remaining_price" => price,
          "payment_schedules" => presets,
          "fixed" => params.fixed,
          "schedule_type" => params.schedule_type
        }
      else
        default_presets = Packages.get_payment_defaults(job_type) |> sort_payment_schedules()

        presets =
          default_presets
          |> Enum.with_index(
            &%{
              "interval" => true,
              "shoot_date" => get_first_shoot(job),
              "last_shoot_date" => get_last_shoot(job),
              "due_interval" => &1,
              "price" => get_price(price, length(default_presets), &2)
            }
          )

        %{
          "total_price" => price,
          "remaining_price" => price,
          "payment_schedules" => presets,
          "fixed" => true,
          "schedule_type" => job_type
        }
      end

    socket
    |> assign_payments_changeset(params, :insert)
    |> assign(step: :payment)
  end

  defp sort_payment_schedules(presets) do
    {first, remaining} =
      Enum.split_with(presets, fn preset ->
        if is_binary(preset) do
          preset == "To Book"
        else
          preset.due_interval == "To Book"
        end
      end)

    List.flatten([first | remaining])
  end

  defp save_payment(socket, %{"custom_payments" => payment_params} = params, job_id \\ nil) do
    socket
    |> maybe_assign_custom(payment_params)
    |> then(fn %{assigns: %{changeset: changeset, payments_changeset: payments_changeset}} =
                 socket ->
      payment_schedules =
        payments_changeset
        |> current()
        |> Map.from_struct()
        |> Map.get(:payment_schedules, [])
        |> Enum.map(&Map.from_struct(&1))

      total_price = Changeset.get_field(payments_changeset, :total_price)
      changeset = update_package_changeset(changeset, payments_changeset)

      opts = %{
        job_id: job_id,
        total_price: total_price,
        payment_schedules: payment_schedules,
        action: :update
      }

      case Packages.insert_or_update_package(changeset, Map.get(params, "contract"), opts) do
        {:ok, package} ->
          successfull_save(
            socket,
            package |> Repo.preload(:package_payment_schedules, force: true)
          )

        _ ->
          socket |> noreply()
      end
    end)
  end

  defp get_preset_options(payments_changeset, payment_preset) do
    payment_schedules =
      payments_changeset
      |> current()
      |> Map.from_struct()
      |> Map.get(:payment_schedules, [])
      |> Enum.map(&Map.from_struct(&1))

    if payment_preset do
      %{
        action: :update_preset,
        payment_preset: payment_preset |> Map.drop([:package_payment_schedules])
      }
    else
      %{action: :insert_preset}
    end
    |> Map.merge(%{payment_schedules: payment_schedules})
  end

  defp template_selected?(form),
    do: form |> current() |> Map.get(:package_template_id) != nil

  # takes the current changeset off the socket and returns a new changeset with the same data but new_opts
  # this is for special cases like "back." mostly we want to use params when we create a changset, not
  # the socket data.
  defp update_changeset(%{assigns: %{changeset: changeset} = assigns}, new_opts) do
    opts = assigns |> Map.take([:is_template, :step]) |> Map.to_list() |> Keyword.merge(new_opts)

    changeset
    |> current()
    |> Package.changeset(%{}, opts)
  end

  defp find_template(socket, "" <> template_id),
    do: find_template(socket, String.to_integer(template_id))

  defp find_template(%{assigns: %{templates: templates}}, template_id),
    do: Enum.find(templates, &(&1.id == template_id))

  defp changeset_from_template(socket, template_id) do
    socket
    |> find_template(template_id)
    |> changeset_from_template()
  end

  defp changeset_from_template(template), do: Packages.changeset_from_template(template)

  defp successfull_save(socket, package) do
    send(self(), {:update, %{package: package}})
    close_modal(socket)

    socket |> noreply()
  end

  defp insert_package_and_update_job(socket, changeset, job, opts) do
    case Packages.insert_package_and_update_job(changeset, job, opts) |> Repo.transaction() do
      {:ok, %{package_update: package}} ->
        successfull_save(socket, package)

      {:ok, %{package: package}} ->
        successfull_save(socket, package)

      {:error, :package, changeset, _} ->
        socket |> assign(changeset: changeset) |> noreply()

      _ ->
        socket
        |> put_flash(:error, "Oops! Something went wrong. Please try again.")
        |> noreply()
    end
  end

  defp insert_package_and_update_booking_event(socket, changeset, booking_event, opts) do
    case Packages.insert_package_and_update_booking_event(changeset, booking_event, opts)
         |> Repo.transaction() do
      {:ok, %{package_update: package}} ->
        successfull_save(socket, package)

      {:ok, %{package: package}} ->
        successfull_save(socket, package)

      {:error, :package, changeset, _} ->
        socket |> assign(changeset: changeset) |> noreply()

      _ ->
        socket
        |> put_flash(:error, "Oops! Something went wrong. Please try again.")
        |> noreply()
    end
  end

  defp build_changeset(%{assigns: assigns}, params),
    do: Packages.build_package_changeset(assigns, params)

  defp assign_changeset(
         %{
           assigns:
             %{
               global_settings: global_settings,
               step: step,
               package: package,
               currency: currency
             } = assigns
         } = socket,
         params,
         action \\ nil
       ) do
    download_params = Map.get(params, "download", %{}) |> Map.put("step", step)

    download_changeset =
      package
      |> Download.from_package(global_settings)
      |> Download.changeset(download_params, Map.get(assigns, :download_changeset))
      |> Map.put(:action, action)

    package_pricing_changeset =
      assigns.package_pricing
      |> PackagePricing.changeset(
        Map.get(params, "package_pricing", package_pricing_params(package))
        |> Map.put("step", step)
      )

    package_pricing = current(package_pricing_changeset)
    download = current(download_changeset)

    print_credits_include_in_total = Map.get(package_pricing, :print_credits_include_in_total)
    digitals_include_in_total = Map.get(download, :digitals_include_in_total)

    multiplier_params = Map.get(params, "multiplier", %{}) |> Map.put("step", step)

    multiplier_changeset =
      package
      |> Multiplier.from_decimal()
      |> Multiplier.changeset(
        multiplier_params,
        print_credits_include_in_total,
        digitals_include_in_total
      )

    multiplier = current(multiplier_changeset)

    package_params =
      params
      |> Map.get("package", %{})
      |> Map.put("currency", currency)
      |> PackagePricing.handle_package_params(params)
      |> Map.merge(%{
        "base_multiplier" => multiplier |> Multiplier.to_decimal(),
        "discount_base_price" => multiplier |> Map.get(:discount_base_price),
        "discount_print_credits" => multiplier |> Map.get(:discount_print_credits),
        "discount_digitals" => multiplier |> Map.get(:discount_digitals),
        "print_credits_include_in_total" =>
          Map.get(package_pricing, :print_credits_include_in_total),
        "digitals_include_in_total" => Map.get(download, :digitals_include_in_total),
        "download_count" => Download.count(download),
        "download_each_price" => Download.each_price(download, currency),
        "buy_all" => Download.buy_all(download),
        "status" => download.status
      })

    changeset = build_changeset(socket, package_params) |> Map.put(:action, action)

    assign(socket,
      changeset: changeset,
      multiplier: multiplier_changeset,
      package_pricing: package_pricing_changeset,
      download_changeset: download_changeset
    )
  end

  defp symbol!(currency), do: Money.Currency.symbol!(currency)

  defp adjust(adjustment) do
    sign = if Money.negative?(adjustment), do: "-", else: "+"
    Enum.join([sign, Money.abs(adjustment)])
  end

  defp base_adjustment(package_form),
    do: package_form |> current() |> Package.base_adjustment() |> adjust()

  defp digitals_adjustment(package_form),
    do: package_form |> current() |> Package.digitals_adjustment() |> adjust()

  defp print_cridets_adjustment(package_form),
    do: package_form |> current() |> Package.print_cridets_adjustment() |> adjust()

  defp total_price(form), do: form |> current() |> Package.price()

  defp next_step(%{step: step, steps: steps}) do
    Enum.at(steps, Enum.find_index(steps, &(&1 == step)) + 1)
  end

  defp assign_contract_changeset(
         %{assigns: %{step: :documents, changeset: changeset}} = socket,
         params
       ) do
    contract_template_id = Map.get(params, "contract_template_id")
    contract_params = Map.get(params, "contract", %{})

    contract =
      if contract_template_id do
        changeset
        |> current()
        |> Contracts.find_by!(contract_template_id)
      else
        changeset
        |> current()
        |> package_contract()
      end

    contract_changeset =
      contract
      |> Contract.changeset(params,
        skip_package_id: true,
        validate_unique_name_on_organization:
          if(validate_contract_name?(contract_params),
            do: socket.assigns.current_user.organization_id
          )
      )
      |> Map.put(:action, :validate)

    socket |> assign(contract_changeset: contract_changeset)
  end

  defp assign_contract_changeset(socket, _params), do: socket

  defp validate_contract_name?(%{"edited" => false, "contract_template_id" => ""}),
    do: true

  defp validate_contract_name?(%{"edited" => true}), do: true

  defp validate_contract_name?(_), do: false

  defp assign_contract_options(%{assigns: %{step: :documents, changeset: changeset}} = socket) do
    options =
      changeset
      |> current()
      |> Contracts.for_package()

    socket |> assign(contract_options: options)
  end

  defp assign_contract_options(socket), do: socket

  defp assign_questionnaires(%{assigns: %{step: :documents, changeset: changeset}} = socket) do
    package =
      changeset
      |> current()

    assign_questionnaires(socket, package.job_type)
  end

  defp assign_questionnaires(
         %{
           assigns: %{
             package: %{job_type: job_type}
           }
         } = socket
       ) do
    assign_questionnaires(socket, job_type)
  end

  defp assign_questionnaires(
         %{
           assigns: %{
             package: %{job_type: nil},
             job: %{type: job_type}
           }
         } = socket,
         %{"package" => _package}
       ) do
    assign_questionnaires(socket, job_type)
  end

  defp assign_questionnaires(
         %{
           assigns: %{
             package: %{job_type: job_type},
             booking_event: _booking_event
           }
         } = socket,
         %{"package" => _package}
       ) do
    assign_questionnaires(socket, job_type)
  end

  defp assign_questionnaires(
         socket,
         %{"package" => %{"job_type" => job_type}}
       ) do
    assign_questionnaires(socket, job_type)
  end

  defp assign_questionnaires(
         %{assigns: %{current_user: %{organization_id: organization_id}}} = socket,
         job_type
       ) do
    socket
    |> assign(
      :questionnaires,
      Questionnaire.for_organization_by_job_type(organization_id, job_type)
    )
  end

  defp package_contract(package) do
    if package.contract do
      assign_turnaround_weeks(package)
    else
      default_contract = Contracts.default_contract(package)

      %Contract{
        content: Contracts.contract_content(default_contract, package, TodoplaceWeb.Helpers),
        contract_template_id: default_contract.id
      }
    end
  end

  defp interval_dropdown_options(field, index) do
    ["To Book", "6 Months Before", "Week Before", "Day Before Shoot"]
    |> Enum.map(&[key: &1, value: &1, disabled: index == 0 && field != &1])
  end

  defp payment_dropdown_options(job_type, schedule_type) do
    options = %{
      "Todoplace #{job_type} default" => job_type,
      "Payment due to book" => "payment_due_book",
      "2 split payments" => "splits_2",
      "3 split payments" => "splits_3"
    }

    cond do
      schedule_type == "custom_#{job_type}" -> %{"Custom for #{job_type}" => "custom_#{job_type}"}
      schedule_type == "custom" -> %{"Custom" => "custom"}
      true -> %{}
    end
    |> Map.merge(options)
  end

  defp hide_add_button(form), do: input_value(form, :payment_schedules) |> length() == 12

  defp get_tags(form, currency), do: make_tags(form, currency) |> Enum.join(", ")

  defp make_tags(form, currency) do
    fixed = input_value(form, :fixed)
    {_, tags} = inputs_for(form, :payment_schedules, &get_tag(&1, fixed, currency))

    tags |> List.flatten()
  end

  defp get_tag(payment_schedule, fixed, currency) do
    if input_value(payment_schedule, :interval) do
      if fixed,
        do: make_due_inteval_tag(payment_schedule, :price, currency),
        else: make_due_inteval_tag(payment_schedule, :percentage)
    else
      shoot_date = input_value(payment_schedule, :shoot_date) |> is_value_set()

      if shoot_date && !input_value(payment_schedule, :count_interval) do
        make_date_tag(payment_schedule, :due_at, currency)
      else
        make_shoot_interval(payment_schedule, currency)
      end
    end
  end

  defp make_shoot_interval(form, currency) do
    value = get_price_value(form, currency)

    if value do
      time = input_value(form, :time_interval)
      count = input_value(form, :count_interval) |> String.to_integer()
      count_interval = if count == 1, do: "1 #{time}", else: "#{count} #{time}s"
      "#{value} #{count_interval} #{input_value(form, :shoot_interval)}"
    else
      ""
    end
  end

  defp make_due_inteval_tag(form, :price = field, currency) do
    value = input_value(form, field) |> is_value_set()

    if value && value != Money.Currency.symbol(currency),
      do: "#{value} #{input_value(form, :due_interval)}",
      else: ""
  end

  defp make_due_inteval_tag(form, field) do
    value = input_value(form, field) |> is_value_set()
    if value && value != "%", do: "#{value}% #{input_value(form, :due_interval)}", else: ""
  end

  defp make_date_tag(form, field, currency) do
    date = input_value(form, field) |> is_value_set()
    value = get_price_value(form, currency)
    if date && value, do: "#{value} at #{date |> Calendar.strftime("%m-%d-%Y")}", else: ""
  end

  defp get_price_value(form, currency) do
    price = input_value(form, :price) |> is_value_set()
    percentage = input_value(form, :percentage) |> is_value_set()

    cond do
      price && price != Money.Currency.symbol!(currency) -> price
      percentage -> "#{percentage}%"
      true -> nil
    end
  end

  defp is_value_set("" <> value), do: if(String.length(value) > 0, do: value, else: false)
  defp is_value_set(value), do: value

  defp get_remaining_price(fixed, value, total) do
    cond do
      fixed == true ->
        value

      Money.zero?(value) ->
        "#{value} (#{0.0}%)"

      true ->
        percentage = value.amount / div(total.amount, 100)
        "#{value} (#{percentage}%)"
    end
  end

  defp map_keys(payments) when is_list(payments) do
    payments
    |> Enum.map(fn payment ->
      payment
      |> Map.from_struct()
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
    end)
  end

  defp map_keys(payment) do
    payment
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp get_custom_payment_defaults(
         %{
           assigns: %{
             custom: custom,
             job_type: job_type,
             custom_schedule_type: custom_schedule_type
           }
         },
         schedule_type,
         _
       ) do
    if custom && schedule_type in ["custom_#{job_type}", "custom"] do
      Packages.get_payment_defaults(custom_schedule_type)
    else
      Packages.get_payment_defaults(schedule_type)
    end
  end

  defp maybe_assign_custom(%{assigns: %{is_template: false, job: _}} = socket, params),
    do: socket |> assign_payments_changeset(params, :validate)

  defp maybe_assign_custom(%{assigns: %{job_type: job_type, default: default}} = socket, params) do
    schedule_type = Map.get(params, "schedule_type")
    custom = default != map_default(params)

    if custom && schedule_type not in ["custom_#{job_type}", "custom"] do
      custom_schedule_type = schedule_type
      schedule_type = if(schedule_type == job_type, do: "custom_#{job_type}", else: "custom")

      socket
      |> assign(custom_schedule_type: custom_schedule_type)
      |> assign_payments_changeset(Map.put(params, "schedule_type", schedule_type), :validate)
    else
      socket
      |> assign_payments_changeset(params, :validate)
    end
    |> assign(custom: custom)
  end

  defp map_default(params) do
    changeset = params |> CustomPayments.changeset()

    %{
      fixed: Changeset.get_field(changeset, :fixed),
      payment_schedules:
        Enum.map(
          Changeset.get_field(changeset, :payment_schedules),
          &Map.take(&1, [:interval, :due_interval])
        )
    }
  end

  defp get_last_shoot(%{id: nil}), do: nil

  defp get_last_shoot(job) do
    shoot = if job, do: get_shoots(job.id) |> List.last(), else: nil
    if shoot, do: shoot.starts_at, else: nil
  end

  defp get_first_shoot(%{id: nil}), do: nil

  defp get_first_shoot(job) do
    shoot = if job, do: get_shoots(job.id) |> List.first(), else: nil
    if shoot, do: shoot.starts_at, else: nil
  end

  defp get_shoots(job_id), do: Shoot.for_job(job_id) |> Repo.all()

  defp tabs_list() do
    [
      %{
        name: "Contract",
        concise_name: "contract"
      },
      %{
        name: "Questionnaire",
        concise_name: "question"
      }
    ]
  end

  defp show_discounts(assigns) do
    ~H"""
    <div class="flex flex-row px-2 items-center w-full self-start mt-3 sm:self-auto justify-self-start sm:mt-0">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp get_discount_text(multiplier) do
    if Map.get(multiplier, :is_enabled) && Multiplier.is_discounts_enabled(multiplier) do
      sign = Map.get(multiplier, :sign)
      sign_text = if sign == "-", do: "discount", else: "surcharge"

      "with #{Map.get(multiplier, :percent)}% #{sign_text}"
    else
      nil
    end
  end
end
