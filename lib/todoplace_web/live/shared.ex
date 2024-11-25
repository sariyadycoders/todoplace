defmodule TodoplaceWeb.Live.Shared do
  use TodoplaceWeb, :html

  import Phoenix.LiveView
  import Phoenix.Component
  import TodoplaceWeb.LiveHelpers
  import TodoplaceWeb.FormHelpers
  import Phoenix.HTML.Form
  import TodoplaceWeb.ShootLive.Shared, only: [duration_options: 0]
  import TodoplaceWeb.Gettext, only: [dyn_gettext: 1]

  import TodoplaceWeb.LiveModal, only: [footer: 1]
  import TodoplaceWeb.GalleryLive.Shared, only: [new_gallery_path: 2]

  import TodoplaceWeb.PackageLive.Shared,
    only: [package_basic_fields: 1, digital_download_fields: 1, current: 1]

  import TodoplaceWeb.JobLive.Shared,
    only: [
      drag_drop: 1,
      files_to_upload: 1,
      renew_uploads: 3,
      error_action: 1
    ]

  require Ecto.Query

  alias Ecto.{Changeset, Multi, Query}
  alias TodoplaceWeb.Shared.ConfirmationComponent

  alias Todoplace.{
    Job,
    Jobs,
    Shoot,
    Client,
    Package,
    PreferredFilter,
    Repo,
    Questionnaire,
    BookingProposal,
    Workers.CleanStore,
    Packages.Download,
    Packages.PackagePricing,
    EmailAutomation.EmailSchedule,
    EmailAutomationSchedules
  }

  alias TodoplaceWeb.Live.Shared.CustomPayments
  alias TodoplaceWeb.Router.Helpers, as: Routes

  defmodule CustomPaymentSchedule do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :price, Money.Ecto.Map.Type
      field :due_date, :date
    end

    def changeset(payment_schedule, attrs \\ %{}) do
      payment_schedule
      |> cast(attrs, [:price, :due_date])
      |> validate_required([:price, :due_date])
      |> Package.validate_money(:price, greater_than: 0)
    end
  end

  defmodule CustomPayments do
    @moduledoc "For setting payments on last step"
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:currency, :string)
      field(:remaining_price, Money.Ecto.Map.Type)
      embeds_many(:payment_schedules, CustomPaymentSchedule)
    end

    def changeset(attrs) do
      %__MODULE__{}
      |> cast(attrs, [:remaining_price, :currency])
      |> cast_embed(:payment_schedules)
      |> validate_total_amount()
    end

    defp validate_total_amount(changeset) do
      remaining = TodoplaceWeb.Live.Shared.remaining_to_collect(changeset)

      if Money.zero?(remaining) do
        changeset
      else
        add_error(changeset, :remaining_price, "is not valid")
      end
    end
  end

  defmodule CustomPagination do
    @moduledoc "For setting custom pagination using limit and offset"
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:first_index, :integer, default: 1)
      field(:last_index, :integer, default: 0)
      field(:total_count, :integer, default: 0)
      field(:limit, :integer, default: 12)
      field(:offset, :integer, default: 0)
    end

    @attrs [:first_index, :last_index, :total_count, :limit, :offset]
    def changeset(struct, attrs \\ %{}) do
      struct
      |> cast(attrs, @attrs)
    end

    def assign_pagination(socket, default_limit),
      do:
        socket
        |> assign_new(:pagination_changeset, fn ->
          changeset(%__MODULE__{}, %{limit: default_limit})
        end)

    def update_pagination(
          %{assigns: %{pagination_changeset: pagination_changeset}} = socket,
          %{"direction" => direction}
        ) do
      pagination = pagination_changeset |> Changeset.apply_changes()

      updated_pagination =
        case direction do
          "back" ->
            pagination
            |> changeset(%{
              first_index: pagination.first_index - pagination.limit,
              offset: pagination.offset - pagination.limit
            })

          _ ->
            pagination
            |> changeset(%{
              first_index: pagination.first_index + pagination.limit,
              offset: pagination.offset + pagination.limit
            })
        end

      socket
      |> assign(:pagination_changeset, updated_pagination)
    end

    def update_pagination(
          %{assigns: %{pagination_changeset: pagination_changeset}} = socket,
          %{"custom_pagination" => %{"limit" => limit}}
        ) do
      limit = to_integer(limit)

      updated_pagination_changeset =
        pagination_changeset
        |> changeset(%{
          limit: limit,
          last_index: limit,
          total_count: pagination_changeset |> current() |> Map.get(:total_count)
        })

      socket
      |> assign(:pagination_changeset, updated_pagination_changeset)
    end

    def reset_pagination(
          %{assigns: %{pagination_changeset: pagination_changeset}} = socket,
          params
        ),
        do:
          socket
          |> assign(
            :pagination_changeset,
            changeset(pagination_changeset |> Changeset.apply_changes(), params)
          )

    def pagination_index(changeset, index),
      do: changeset |> current() |> Map.get(index)
  end

  def step_number(name, steps), do: Enum.find_index(steps, &(&1 == name)) + 1

  def total_remaining_amount(package_changeset) do
    currency = Changeset.get_field(package_changeset, :currency)
    fallback_price = Money.new(0, currency)

    Money.subtract(
      Changeset.get_field(package_changeset, :base_price) || fallback_price,
      Changeset.get_field(package_changeset, :collected_price) || fallback_price
    )
  end

  def remaining_to_collect(payments_changeset) do
    %{
      remaining_price: remaining_price,
      currency: currency,
      payment_schedules: payments
    } = payments_changeset |> current()

    total_collected =
      payments
      |> Enum.reduce(Money.new(0, currency), fn payment, acc ->
        Money.add(acc, payment.price || Money.new(0, currency))
      end)

    Money.subtract(remaining_price, total_collected)
  end

  def remaining_amount_zero?(package_changeset),
    do: package_changeset |> total_remaining_amount() |> Money.zero?()

  def base_price_zero?(package_changeset),
    do: (Changeset.get_field(package_changeset, :base_price) || Money.new(0)) |> Money.zero?()

  def maybe_insert_payment_schedules(multi_changes, %{assigns: assigns}) do
    if remaining_amount_zero?(assigns.package_changeset) do
      multi_changes
    else
      multi_changes
      |> Ecto.Multi.insert_all(:payment_schedules, Todoplace.PaymentSchedule, fn changes ->
        assigns.payments_changeset
        |> current()
        |> Map.get(:payment_schedules)
        |> Enum.with_index()
        |> make_payment_schedule(changes)
      end)
    end
  end

  def serialize(data), do: data |> :erlang.term_to_binary() |> Base.encode64()
  def deserialize(data), do: data |> Base.decode64!() |> :erlang.binary_to_term()

  defp make_payment_schedule(multi_changes, changes) do
    multi_changes
    |> Enum.map(fn {payment_schedule, i} ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, due_at} =
        payment_schedule.due_date
        |> DateTime.new(~T[00:00:00])

      %{
        price: payment_schedule.price,
        due_at: due_at,
        job_id: changes.job.id,
        inserted_at: now,
        updated_at: now,
        description: "Payment #{i + 1}"
      }
    end)
  end

  def heading_subtitle(step) do
    Map.get(
      %{
        get_started: "Get Started",
        choose_type: "Get Started",
        add_client: "General Details",
        job_details: "General Details",
        details: "General Details",
        package_payment: "Package & Payment",
        pricing: "Pricing",
        invoice: "Custom Invoice",
        documents: "Documents (optional)"
      },
      step
    )
  end

  def make_popup(socket, opts) do
    socket
    |> ConfirmationComponent.open(%{
      close_label: opts[:close_label] || "No, go back",
      confirm_event: opts[:event] || opts[:confirm_event],
      class: "dialog-photographer",
      confirm_class: Keyword.get(opts, :confirm_class, "btn-warning"),
      confirm_label: Keyword.get(opts, :confirm_label, "Yes, delete"),
      icon: Keyword.get(opts, :icon, "warning-orange"),
      title: opts[:title],
      subtitle: opts[:subtitle],
      dropdown?: opts[:dropdown?] || nil,
      dropdown_label: opts[:dropdown_label] || nil,
      dropdown_items: opts[:dropdown_items] || nil,
      empty_dropdown_description: opts[:empty_dropdown_description] || nil,
      copy_btn_label: opts[:copy_btn_label] || nil,
      copy_btn_event: opts[:copy_btn_event] || nil,
      copy_btn_value: opts[:copy_btn_value] || nil,
      purchased: opts[:purchased],
      replace_event: opts[:replace_event],
      payload: Keyword.get(opts, :payload, %{})
    })
    |> noreply()
  end

  def package_payment_step(%{package_changeset: package_changeset} = assigns) do
    assigns =
      assigns
      |> assign(base_price_zero?: base_price_zero?(package_changeset))
      |> Enum.into(%{currency: nil, is_package_tab_clicked?: false, package_details_show?: false})

    ~H"""
    <.form
      :let={f}
      for={@package_changeset}
      phx-change="validate"
      phx-target={@myself}
      id={"form-#{@step}"}
    >
      <h2 class="text-xl font-bold">Package Details</h2>
      <.package_basic_fields form={f} job_type={@job_type} show_no_of_shoots?={false} />

      <div class="flex items-center gap-6 pb-2 border-b-4 border-blue-planning-300 pl-3 mt-6 font-bold">
        <div
          phx-click="package_or_shoot_details_show"
          phx-target={@myself}
          phx-value-shoot_details_show="shoot_details_show"
          class={
            classes("cursor-pointer flex items-center text-blue-planning-300", %{
              "text-black py-1 px-2 bg-blue-planning-100" => !@package_details_show?
            })
          }
        >
          Shoot Details
          <%= if length(@shoots_changeset) == 0 do %>
            <span class={
              classes("text-red-sales-300 bg-base-100 ml-2 rounded-lg px-2 text-sm", %{
                "bg-red-sales-100" => @package_details_show?
              })
            }>
              Todo
            </span>
          <% end %>
        </div>

        <div
          phx-click="package_or_shoot_details_show"
          phx-target={@myself}
          phx-value-package_details_show="package_details_show"
          class={
            classes("cursor-pointer flex items-center text-blue-planning-300", %{
              "text-black py-1 px-2 bg-blue-planning-100" => @package_details_show?
            })
          }
        >
          Package & Pricing Details
          <%= if @is_package_tab_clicked? == false do %>
            <span class={
              classes("text-red-sales-300 bg-base-100 ml-2 rounded-lg px-2 text-sm", %{
                "bg-red-sales-100" => !@package_details_show?
              })
            }>
              Todo
            </span>
          <% end %>
        </div>
      </div>

      <div class={classes("lg:w-3/4", %{"hidden" => !@package_details_show?})}>
        <h2 class="mt-4 mb-2 text-xl font-bold">Package Price</h2>
        <div class="flex flex-col mt-6 items-start justify-between w-full sm:items-center sm:flex-row sm:w-auto">
          <label class="font-bold" for={input_id(f, :base_price)}>
            The amount you’ve charged for your job
            <p class="text-base-250 font-normal">(including download credits)</p>
          </label>
          <div class="flex items-center justify-end w-full mt-6 sm:mt-0 sm:w-auto">
            <span class="mx-3 text-2xl font-bold text-black pb-2.5">+</span>
            <%= input(f, :base_price,
              placeholder: "#{@currency_symbol}0.00",
              class: "sm:w-32 w-full px-4 text-lg text-center",
              phx_hook: "PriceMask",
              data_currency: @currency_symbol
            ) %>
          </div>
        </div>
        <hr class="mt-6" />
        <div class="flex flex-col mt-6 items-start justify-between w-full sm:items-center sm:flex-row sm:w-auto">
          <label class="font-bold" for={input_id(f, :print_credits)}>
            How much of the creative session fee is for print credits?
          </label>
          <div class="flex items-center justify-end w-full mt-6 sm:mt-0 sm:w-auto">
            <span class="mx-4 text-2xl font-bold text-base-250">&nbsp;</span>
            <%= input(f, :print_credits,
              disabled: @base_price_zero?,
              placeholder: "#{@currency_symbol}0.00",
              class: "sm:w-32 w-full px-4 text-lg text-center",
              phx_hook: "PriceMask",
              data_currency: @currency_symbol
            ) %>
          </div>
        </div>
        <hr class="mt-6" />
        <div class="flex flex-col mt-6 items-start justify-between w-full sm:items-center sm:flex-row sm:w-auto ">
          <label class="font-bold" for={input_id(f, :collected_price)}>
            The amount you’ve already collected
          </label>
          <div class="flex items-center justify-end w-full mt-6 sm:mt-0 sm:w-auto">
            <span class="mx-3 text-2xl font-bold text-black pb-2.5">-</span>
            <%= input(f, :collected_price,
              disabled: @base_price_zero?,
              placeholder: "#{@currency_symbol}0.00",
              class: "sm:w-32 w-full px-4 text-lg text-center",
              phx_hook: "PriceMask",
              data_currency: @currency_symbol
            ) %>
          </div>
        </div>
        <hr class="mt-6" />
        <dl
          class="flex flex-col mt-6 justify-between text-lg font-bold sm:flex-row"
          {testid("remaining-balance")}
        >
          <dt>Remaining balance to collect with Todoplace</dt>
          <dd class="w-full p-6 py-2 mt-2 text-center rounded-lg sm:w-32 text-green-finances-300 bg-green-finances-100/30 sm:mt-0">
            <%= total_remaining_amount(@package_changeset) %>
          </dd>
        </dl>

        <hr class="mt-4 border-gray-100" />

        <%= if @package_details_show? do %>
          <.digital_download_fields
            for={:import_job}
            package_form={f}
            currency={@currency}
            currency_symbol={@currency_symbol}
            download_changeset={@download_changeset}
            package_pricing={@package_pricing_changeset}
            target={@myself}
            show_digitals={@show_digitals}
          />
        <% end %>
      </div>

      <div class={classes("", %{"hidden" => @package_details_show?})}>
        <%= unless Enum.any? @shoots_changeset do %>
          <div class="p-3 flex items-center gap-3 border border-base-200 rounded-lg my-4">
            <div>
              <.icon name="empty-shoot" class="h-4 w-4 mr-2 text-blue-planning-300"></.icon>
            </div>
            <div>
              You need at least one shoot date to proceed. Add one below.
            </div>
          </div>
        <% end %>
        <.package_shoot_block
          shoots_changeset={@shoots_changeset}
          myself={@myself}
          current_user={@current_user}
          step={@step}
        />
        <.icon_button
          phx-click="add-shoot"
          phx-target={@myself}
          class="mt-4 text-black"
          title=""
          color="blue-planning-300"
          icon="plus"
        >
          Add Shoot
        </.icon_button>
      </div>

      <.footer>
        <% disabled_condition =
          Enum.any?(
            [@download_changeset, @package_pricing_changeset, @package_changeset],
            &(!&1.valid?)
          ) or @is_any_shoot_invalid? %>
        <button
          class="px-8 btn-primary"
          phx-click="submit-payment-step"
          phx-target={@myself}
          title="Next"
          disabled={disabled_condition}
          phx-disable-with="Next"
        >
          Next
        </button>
        <button
          class="btn-secondary"
          title="cancel"
          type="button"
          phx-click="back"
          phx-target={@myself}
        >
          Go back
        </button>
      </.footer>
    </.form>
    """
  end

  def invoice_step(%{package_changeset: package_changeset} = assigns) do
    assigns = assign(assigns, remaining_amount_zero?: remaining_amount_zero?(package_changeset))

    ~H"""
    <.form
      :let={f}
      for={@payments_changeset}
      phx-change="validate"
      phx-submit="submit"
      phx-target={@myself}
      id={"form-#{@step}"}
    >
      <h3 class="font-bold">Balance to collect: <%= total_remaining_amount(@package_changeset) %></h3>

      <div
        class={
          classes("flex items-center bg-blue-planning-100 rounded-lg my-4 py-4", %{
            "hidden" => !@remaining_amount_zero?
          })
        }
        }
      >
        <.tooltip class="ml-4" content="#" id="currency" />
        <div class="pl-2">
          <b>
            Since your remaining balance is <%= @currency_symbol %>0.00, we'll mark your job as paid for.
          </b>
          Make sure to follow up with any emails as needed to your client.
        </div>
      </div>

      <div class={classes(%{"pointer-events-none opacity-40" => @remaining_amount_zero?})}>
        <%= inputs_for f, :payment_schedules, fn p -> %>
          <div {testid("payment-#{p.index + 1}")}>
            <div class="flex items-center mt-4">
              <div class="mb-2 text-xl font-bold">Payment <%= p.index + 1 %></div>

              <%= if p.index > 0 do %>
                <.icon_button
                  class="ml-8"
                  title="remove"
                  phx-click="remove-payment"
                  phx-target={@myself}
                  color="red-sales-300"
                  icon="trash"
                >
                  Remove
                </.icon_button>
              <% end %>
            </div>

            <div class="flex flex-wrap w-full mb-8">
              <div class="w-full sm:w-auto">
                <.date_picker_field
                  class="sm:w-64 w-full text-lg"
                  id={"payment-#{p.index}"}
                  form={p}
                  field={:due_date}
                  input_placeholder="mm/dd/yyyy"
                  input_label="Due"
                />
              </div>
              <div class="w-full sm:ml-16 sm:w-auto">
                <%= labeled_input(p, :price,
                  label: "Payment amount",
                  placeholder: "#{@currency_symbol}0.00",
                  class: "sm:w-36 w-full px-4 text-lg text-center",
                  phx_hook: "PriceMask",
                  data_currency: @currency_symbol
                ) %>
              </div>
            </div>
          </div>
        <% end %>

        <%= if f |> current() |> Map.get(:payment_schedules) |> Enum.count == 1 do %>
          <button
            type="button"
            title="add"
            phx-click="add-payment"
            phx-target={@myself}
            class="px-2 py-1 mb-8 btn-secondary"
          >
            Add new payment
          </button>
        <% end %>

        <div class="text-xl font-bold">
          Remaining to collect:
          <%= case remaining_to_collect(@payments_changeset) do %>
            <% value -> %>
              <%= if Money.zero?(value) do %>
                <span class="text-green-finances-300"><%= value %></span>
              <% else %>
                <span class="text-red-sales-300"><%= value %></span>
              <% end %>
          <% end %>
        </div>
        <p class="mb-2 text-sm italic font-light">limit two payments</p>
      </div>
      <.footer>
        <button
          class="px-8 btn-primary"
          title="Next"
          type="submit"
          disabled={if @remaining_amount_zero?, do: false, else: !@payments_changeset.valid?}
          phx-disable-with="Next"
        >
          Next
        </button>
        <button
          class="btn-secondary"
          title="cancel"
          type="button"
          phx-click="back"
          phx-target={@myself}
        >
          Go back
        </button>
      </.footer>
    </.form>
    """
  end

  def documents_step(assigns) do
    ~H"""
    <form phx-change="validate" phx-submit="submit" phx-target={@myself} id={"form-#{@step}"}>
      <.drag_drop upload_entity={@uploads.documents} supported_types=".PDF, .docx, .txt" />
      <div class={
        classes("mt-8", %{
          "hidden" => Enum.empty?(@uploads.documents.entries ++ @ex_documents ++ @invalid_entries)
        })
      }>
        <div
          class="grid grid-cols-5 pb-4 items-center text-lg font-bold"
          id="import_job_resume_upload"
          phx-hook="ResumeUpload"
        >
          <span class="col-span-2">Name</span>
          <span class="col-span-1 text-center">Status</span>
          <span class="ml-auto col-span-2">Actions</span>
        </div>
        <hr class="md:block border-blue-planning-300 border-2 mb-2" />
        <%= Enum.map(@invalid_entries, fn entry -> %>
          <.files_to_upload myself={@myself} entry={entry} for={:job}>
            <.error_action error={@invalid_entries_errors[entry.ref]} entry={entry} target={@myself} />
          </.files_to_upload>
        <% end) %>
        <%= Enum.map(@uploads.documents.entries ++ @ex_documents, fn entry -> %>
          <.files_to_upload myself={@myself} entry={entry} for={:job}>
            <p class="btn items-center">
              <%= if entry.done?, do: "Uploaded", else: "Uploading..." %>
            </p>
          </.files_to_upload>
        <% end) %>
      </div>

      <div class="pt-40"></div>

      <div
        {testid("modal-buttons")}
        class="sticky px-4 -m-4 bg-white -bottom-6 sm:px-8 sm:-m-8 sm:-bottom-8"
      >
        <div class="flex flex-col py-6 bg-white gap-2 sm:flex-row-reverse">
          <button
            class="px-8 btn-primary"
            title="Save"
            type="submit"
            disabled={Enum.any?(@invalid_entries)}
            phx-disable-with="Finish"
          >
            Save
          </button>
          <button
            class="btn-secondary"
            title="cancel"
            type="button"
            phx-click="back"
            phx-target={@myself}
          >
            Go back
          </button>
          <a
            {testid("import-another-job-link")}
            class="z-100 flex items-center underline mr-5 cursor-pointer text-blue-planning-300 justify-center"
            phx-click="start_another_job"
            phx-target={@myself}
          >
            <.icon name="refresh-icon" class="h-4 w-4 mr-2 text-blue-planning-300"></.icon>
            <%= "Start another job import for #{cond do
              @searched_client -> @searched_client.name
              @selected_client -> @selected_client.name
              @client_name -> @client_name
              true -> Changeset.get_field(@job_changeset.changes.client, :name)
            end}" %>
          </a>
        </div>
      </div>
    </form>
    """
  end

  defp package_shoot_block(assigns) do
    ~H"""
    <%= Enum.with_index(@shoots_changeset, fn shoot_changeset, index -> %>
      <div class="rounded-lg my-6 border border-base-200">
        <div class="rounded-t-lg bg-base-200 flex items-center justify-between p-3">
          <div class="text-lg font-bold">
            <%= "Shoot #{index + 1}" %>
          </div>
          <.icon_button
            phx-click="remove-shoot"
            phx-value-shoot_index={index + 1}
            phx-target={@myself}
            class="bg-white text-red-sales-300"
            title=""
            color="red-sales-300"
            icon="trash"
          >
            Remove
          </.icon_button>
        </div>
        <.form
          :let={f}
          for={shoot_changeset}
          phx-change="validate"
          phx-value-shoot_index={index}
          phx-submit=""
          phx-target={@myself}
          id={"form-#{@step}-#{index}"}
        >
          <div class="p-3 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            <div>
              <%= labeled_input(f, :name,
                label: "Shoot Title",
                placeholder: "e.g.",
                wrapper_class: ""
              ) %>
            </div>
            <div class="flex items-end">
              <.date_picker_field
                class="flex flex-col w-full"
                id={"shoot-time-#{index}"}
                placeholder="Select shoot time…"
                form={f}
                field={:starts_at}
                input_placeholder="mm/dd/yyyy"
                input_label="Shoot Date"
                data_custom_date_format="Y-m-d\\TH:i"
                data_time_picker="true"
                data_time_zone={@current_user.time_zone}
              />
            </div>
            <div>
              <%= labeled_select(f, :duration_minutes, duration_options(),
                label: "Shoot Duration",
                prompt: "Select below"
              ) %>
            </div>

            <div class="flex flex-col">
              <div class="flex items-center justify-between">
                <%= label_for(f, :location, label: "Shoot Location") %>
              </div>

              <%= select_field(
                f,
                :location,
                for(
                  location <- Shoot.locations(),
                  do: {location |> Atom.to_string() |> dyn_gettext(), location}
                ),
                prompt: "Select below",
                disabled: false
              ) %>
            </div>

            <div class="flex flex-col">
              <div class="flex items-center justify-between">
                <%= label_for(f, :address, label: "Shoot Address") %>
              </div>

              <%= input(f, :address,
                phx_hook: "PlacesAutocomplete",
                autocomplete: "off",
                placeholder: "Enter a location",
                disabled: false
              ) %>
              <div
                class="relative autocomplete-wrapper"
                id={"auto-complete-#{index}"}
                phx-update="ignore"
              >
              </div>
            </div>
          </div>
        </.form>
      </div>
    <% end) %>
    """
  end

  def client_name_box(%{assigns: %{job_changeset: _}} = assigns) do
    assigns = assigns |> Enum.into(%{changeset: nil})

    ~H"""
    <div class="flex items-center hover:cursor-auto gap-2">
      <div class="ml-2 text-base-200 hidden md:block">|</div>
      <div class="w-7 h-7 flex items-center justify-center bg-blue-planning-300 rounded-full">
        <.icon name="client-icon" class="w-4 h-4 text-white"></.icon>
      </div>
      <p class="font-bold">
        Client:
        <span class="font-normal">
          <%= cond do
            @changeset -> Changeset.get_field(@changeset, :name)
            @searched_client -> @searched_client.name
            @selected_client -> @selected_client.name
            true -> Changeset.get_field(@assigns.job_changeset.changes.client, :name)
          end %>
        </span>
      </p>
    </div>
    """
  end

  def go_back_event(
        "back",
        %{},
        %{assigns: %{step: step, steps: steps}} = socket
      ) do
    previous_step = Enum.at(steps, Enum.find_index(steps, &(&1 == step)) - 1)

    socket
    |> assign(
      step:
        if(previous_step == :get_started,
          do: step,
          else: previous_step
        )
    )
  end

  def go_back_event(
        "back",
        %{},
        %{assigns: %{step: step, steps: steps, selected_client: selected_client}} = socket
      ) do
    previous_step = Enum.at(steps, Enum.find_index(steps, &(&1 == step)) - 1)

    socket
    |> assign(
      step:
        if(!is_nil(selected_client) and previous_step == :get_started,
          do: step,
          else: previous_step
        )
    )
  end

  def remove_payment_event(
        "remove-payment",
        %{},
        %{assigns: %{payments_changeset: payments_changeset}} = socket
      ) do
    payment_schedule =
      payments_changeset
      |> current()
      |> Map.get(:payment_schedules)
      |> Enum.at(0)
      |> Map.from_struct()
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    params = %{"payment_schedules" => [payment_schedule]}

    socket
    |> assign_payments_changeset(params, :validate)
  end

  def add_payment_event(
        "add-payment",
        %{},
        %{assigns: %{payments_changeset: payments_changeset}} = socket
      ) do
    payment_schedules =
      payments_changeset
      |> current()
      |> Map.get(:payment_schedules)
      |> Enum.map(fn payment ->
        payment
        |> Map.from_struct()
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
      end)

    params = %{"payment_schedules" => payment_schedules ++ [%{}]}

    socket
    |> assign_payments_changeset(params, :validate)
  end

  def invoice_submit_event("submit", %{}, %{assigns: %{step: :invoice}} = socket),
    do: socket |> assign(:step, :documents)

  def payment_package_submit_event(
        "submit",
        params,
        %{assigns: %{step: :package_payment}} = socket
      ) do
    case socket |> assign_package_changeset(params, :validate) do
      %{
        assigns: %{
          package_changeset: %{valid?: true} = package_changeset,
          download_changeset: %{valid?: true},
          package_pricing_changeset: %{valid?: true},
          payments_changeset: payments_changeset,
          is_any_shoot_invalid?: false
        }
      } ->
        socket
        |> assign(
          step: :invoice,
          payments_changeset:
            payments_changeset
            |> Changeset.put_change(
              :remaining_price,
              total_remaining_amount(package_changeset)
            )
        )

      socket ->
        socket
    end
  end

  def is_any_shoot_invalid?(nil), do: false

  def is_any_shoot_invalid?([]), do: true

  def is_any_shoot_invalid?(shoots_changeset),
    do: Enum.any?(shoots_changeset, &(&1.valid? == false))

  def validate_package_event("validate", %{"package" => _} = params, socket),
    do: socket |> assign_package_changeset(params, :validate)

  def validate_payments_event("validate", %{"custom_payments" => params}, socket),
    do: socket |> assign_payments_changeset(params, :validate)

  def assign_payments_changeset(
        %{assigns: %{package_changeset: package_changeset, currency: currency}} = socket,
        params,
        action \\ nil
      ) do
    changeset =
      params
      |> Map.put("remaining_price", total_remaining_amount(package_changeset))
      |> Map.put("currency", currency)
      |> CustomPayments.changeset()
      |> Map.put(:action, action)

    assign(socket, payments_changeset: changeset)
  end

  def assign_package_changeset(
        %{
          assigns:
            %{
              current_user: current_user,
              step: step,
              currency: currency
            } = assigns
        } = socket,
        params,
        action \\ nil
      ) do
    type = Ecto.Changeset.get_change(socket.assigns.job_changeset, :type)
    shoots_changeset = Map.get(assigns, :shoots_changeset)
    is_any_shoot_invalid? = is_any_shoot_invalid?(shoots_changeset)
    shoot_count = if shoots_changeset, do: Enum.count(shoots_changeset)

    package_pricing_changeset =
      Map.get(params, "package_pricing", %{})
      |> PackagePricing.changeset()
      |> Map.put(:action, action)

    global_settings = Todoplace.GlobalSettings.get(current_user.organization_id)

    download_params = Map.get(params, "download", %{}) |> Map.put("step", step)

    download_changeset =
      assigns.package
      |> Download.from_package(global_settings)
      |> Download.changeset(download_params, Map.get(assigns, :download_changeset))
      |> Map.put(:action, action)

    download = current(download_changeset)

    package_changeset =
      params
      |> Map.get("package", %{})
      |> Map.put("currency", currency)
      |> Map.put("shoot_count", shoot_count)
      |> PackagePricing.handle_package_params(params)
      |> Map.merge(%{
        "download_count" => Download.count(download),
        "download_each_price" => Download.each_price(download, currency),
        "organization_id" => current_user.organization_id,
        "buy_all" => Download.buy_all(download),
        "status" => download.status,
        "job_type" => type
      })
      |> Package.import_changeset()
      |> Map.put(:action, action)

    assign(socket,
      package_changeset: package_changeset,
      download_changeset: download_changeset,
      package_pricing_changeset: package_pricing_changeset,
      is_any_shoot_invalid?: is_any_shoot_invalid?
    )
  end

  def import_job_for_import_wizard(
        %{
          assigns: %{
            selected_client: selected_client,
            searched_client: searched_client,
            job_changeset: job_changeset
          }
        } = socket
      ) do
    job = job_changeset |> Changeset.apply_changes()
    client = get_client(selected_client, searched_client, job.client)
    job_changeset = job_changeset |> Changeset.delete_change(:client)

    socket
    |> save_multi(client, job_changeset, "import_wizard")
  end

  def import_job_for_form_component(
        %{assigns: %{changeset: changeset, job_changeset: job_changeset}} = socket
      ) do
    client = %Client{
      name: Changeset.get_field(changeset, :name),
      email: Changeset.get_field(changeset, :email)
    }

    socket
    |> save_multi(client, job_changeset, "form_component")
  end

  def update_package_questionnaire(
        %{
          assigns: %{
            current_user: current_user,
            package: %{questionnaire_template_id: nil} = package
          }
        } = socket
      ) do
    template = get_template(socket)

    case Questionnaire.insert_questionnaire_for_package(template, current_user, package) do
      {:ok, %{questionnaire_insert: questionnaire_insert}} ->
        socket
        |> open_questionnaire_modal(:edit_lead, questionnaire_insert)

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to fetch questionnaire. Please try again.")
    end
  end

  def update_package_questionnaire(%{assigns: %{package: package}} = socket) do
    socket
    |> open_questionnaire_modal(:edit_lead, package.questionnaire_template)
    |> noreply()
  end

  def open_questionnaire_modal(
        %{assigns: %{current_user: current_user}} = socket,
        state,
        questionnaire
      ) do
    socket
    |> TodoplaceWeb.QuestionnaireFormComponent.open(%{
      state: state,
      current_user: current_user,
      questionnaire: questionnaire
    })
  end

  defp save_multi(
         %{
           assigns: %{
             current_user: current_user,
             package_changeset: package_changeset,
             shoots_changeset: shoots_changeset,
             ex_documents: ex_documents,
             another_import: another_import
           }
         } = socket,
         client,
         job_changeset,
         type
       ) do
    Multi.new()
    |> Jobs.maybe_upsert_client(client, current_user)
    |> Multi.insert(:job, fn changes ->
      job_changeset
      |> Changeset.put_change(:client_id, changes.client.id)
      |> Job.document_changeset(%{
        documents: Enum.map(ex_documents, &%{name: &1.client_name, url: &1.path})
      })
      |> Map.put(:action, nil)
    end)
    |> Multi.insert_all(:shoots, Shoot, fn change ->
      Enum.map(shoots_changeset, fn shoot ->
        naive_datetime =
          Timex.now() |> Timex.to_naive_datetime() |> NaiveDateTime.truncate(:second)

        shoot
        |> Changeset.put_change(:job_id, change.job.id)
        |> current()
        |> Map.from_struct()
        |> Map.drop([:__meta__, :id, :job])
        |> Map.put(:inserted_at, naive_datetime)
        |> Map.put(:updated_at, naive_datetime)
      end)
    end)
    |> Multi.run(:cancel_oban_jobs, fn _repo, _ ->
      Oban.Job
      |> Query.where(worker: "Todoplace.Workers.CleanStore")
      |> Query.where([oban], oban.id in ^Enum.map(ex_documents, & &1.oban_job_id))
      |> Oban.cancel_all_jobs()
    end)
    |> Multi.insert(:package, package_changeset |> Map.put(:action, nil))
    |> Multi.update(:job_update, fn changes ->
      Job.add_package_changeset(changes.job, %{package_id: changes.package.id})
    end)
    |> Multi.insert(:proposal, fn changes ->
      BookingProposal.changeset(%{job_id: changes.job.id})
    end)
    |> maybe_insert_payment_schedules(socket)
    |> Ecto.Multi.insert_all(:email_automation, EmailSchedule, fn %{
                                                                    job: %Job{
                                                                      id: job_id,
                                                                      type: type
                                                                    }
                                                                  } ->
      EmailAutomationSchedules.job_emails(type, current_user.organization_id, job_id, :job, [
        :thanks_booking,
        :thanks_job
      ])
    end)
    |> Repo.transaction()
    |> then(fn
      {:ok, %{job: job}} ->
        socket =
          if another_import do
            socket
            |> assign(:another_import, false)
            |> assign(:ex_documents, [])
            |> assign(
              if(type == "import_wizard",
                do: %{step: :job_details},
                else: %{step: :package_payment}
              )
            )
            |> assign_package_changeset(%{})
            |> assign_payments_changeset(%{"payment_schedules" => [%{}, %{}]})
          else
            socket |> push_navigate(to: ~p"/clients/#{job.client_id}/job-history")
          end

        socket

      {:error, _} ->
        socket
    end)
  end

  def save_filters(
        organization_id,
        type,
        filters
      ) do
    case PreferredFilter.load_preferred_filters(organization_id, type) do
      nil ->
        PreferredFilter.changeset(%PreferredFilter{}, %{
          organization_id: organization_id,
          type: type,
          filters: filters
        })
        |> Repo.insert_or_update()

      preferred_filters ->
        PreferredFilter.changeset(preferred_filters, %{
          organization_id: organization_id,
          type: type,
          filters: filters
        })
        |> Repo.insert_or_update()
    end
  end

  defp get_client(selected_client, searched_client, client) do
    cond do
      selected_client ->
        selected_client

      searched_client ->
        searched_client

      true ->
        client
    end
  end

  @scheduled_at_hours 2
  def handle_progress(
        :documents,
        entry,
        %{assigns: %{ex_documents: ex_documents, uploads: %{documents: %{entries: entries}}}} =
          socket
      ) do
    if entry.done? do
      key = Job.document_path(entry.client_name, entry.uuid)
      opts = [scheduled_at: Timex.now() |> Timex.shift(hours: @scheduled_at_hours)]
      oban_job = CleanStore.new(%{path: key}, opts) |> Oban.insert!()
      new_entry = Map.put(entry, :path, key) |> Map.put(:oban_job_id, oban_job.id)

      entries
      |> Enum.reject(&(&1.uuid == entry.uuid))
      |> renew_uploads(entry, socket)
      |> assign(:ex_documents, [new_entry | ex_documents])
      |> noreply()
    else
      socket |> noreply()
    end
  end

  def handle_info({:redirect_to_gallery, gallery}, socket) do
    socket
    |> put_flash(:success, "Gallery created—You’re now ready to upload photos!")
    |> push_redirect(to: new_gallery_path(socket, gallery))
    |> noreply()
  end

  defp get_template(%{assigns: %{job: job}}),
    do: Questionnaire.for_job(job)

  defp get_template(%{assigns: %{package: package}}),
    do: Questionnaire.for_package(package)
end
