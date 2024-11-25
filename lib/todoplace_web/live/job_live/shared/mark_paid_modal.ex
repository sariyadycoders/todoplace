defmodule TodoplaceWeb.JobLive.Shared.MarkPaidModal do
  @moduledoc false
  use TodoplaceWeb, :live_component

  alias Todoplace.{
    Repo,
    EmailAutomationSchedules,
    PaymentSchedule,
    PaymentSchedules,
    Job,
    Currency,
    EmailAutomations
  }

  import Ecto.Query
  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> then(&assign(&1, changeset: build_changeset(&1)))
    |> assign(:add_payment_show, false)
    |> assign_payments()
    |> assign_job()
    |> assign_currency()
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal">
      <h1 id="payment-modal" class="flex justify-between mb-4 pl-3 text-3xl font-bold">
        Mark <%= action_name(@live_action, :plural) %> as paid
        <button
          id="close"
          phx-click="modal"
          phx-value-action="close"
          title="close modal"
          type="button"
          class="p-2"
        >
          <.icon name="close-x" class="w-3 h-3 stroke-current stroke-2 sm:stroke-1 sm:w-6 sm:h-6" />
        </button>
      </h1>
      <div>
        <div class="flex items-center justify-start">
          <dl class="flex flex-col">
            <dd class="pr-32 pl-3">
              <b> Balance to collect </b>
              <button
                id="send-email-link"
                class="link block text-xs"
                phx-click="open-compose"
                phx-value-client_id={@job.client_id}
                phx-target={@myself}
              >
                Send reminder email
              </button>
            </dd>
          </dl>
          <h1 id="amount" class="rounded-lg bg-base-200 px-5 py-2">
            <%= PaymentSchedules.owed_offline_price(assigns.job) %>
          </h1>
        </div>
        <table class="table-auto w-full mt-8">
          <thead class="bg-base-200 pl-3 py-2">
            <tr class="border-base-200">
              <th class="p-3 text-left bg-base-200" id="job-name"><%= Job.name(@job) %></th>
              <th class="p-3 text-left bg-base-200">Amount</th>
              <th class="p-3 text-left bg-base-200">Type</th>
              <th class="p-3 text-left bg-base-200">Status</th>
            </tr>
          </thead>
          <tbody>
            <%= @payment_schedules |> Enum.with_index |> Enum.map(fn({payment_schedule, index}) -> %>
              <tr class={"#{!(index  == (Enum.count(@payment_schedules)-1)) && "border-b"}"}>
                <td id="payments" class="font-bold font-sans pl-3 my-2">Payment <%= index + 1 %></td>
                <td class="pl-3 py-2" id="offline-amount"><%= payment_schedule.price %></td>
                <td class="pl-3 py-2"><%= String.capitalize(payment_schedule.type) %></td>
                <td class="text-green-finances-300 pl-3 py-2">
                  Paid <%= strftime(@current_user.time_zone, payment_schedule.paid_at, "%b %d, %Y") %>
                </td>
              </tr>
              <hr />
            <% end ) %>
          </tbody>
        </table>
        <%= if PaymentSchedules.owed_offline_price(assigns.job) |> Map.get(:amount) > 0 do %>
          <%= if !@add_payment_show do %>
            <.icon_button
              id="add-payment"
              class="border-solid border-2 border-blue-planning-300 rounded-md my-8 px-10 pb-1.5 flex items-center"
              title="Add a payment"
              color="blue-planning-300"
              icon="plus"
              phx-click="select_add_payment"
              phx-target={@myself}
            >
              Add a payment
            </.icon_button>
          <% end %>
        <% end %>
        <%= if @add_payment_show do %>
          <div class="rounded-lg border border-base-200 mt-2">
            <h1 class="mb-4 rounded-t-lg bg-base-200 p-3 text-xl font-bold">Add a payment</h1>
            <.form
              :let={f}
              id="add-payment-form"
              for={@changeset}
              phx-submit="save"
              phx-target={@myself}
              phx-change="validate"
            >
              <div class="mx-5 grid grid-cols-3 gap-12">
                <dl>
                  <dd>
                    <%= labeled_input(f, :price,
                      placeholder: "#{@currency_symbol}0.00",
                      label: "Payment Amount",
                      class:
                        "w-full px-4 text-lg mt-6 sm:mt-0 sm:font-normal font-bold text-center h-12",
                      phx_hook: "PriceMask",
                      data_currency: @currency_symbol
                    ) %>
                  </dd>
                  <%= text_input(f, :currency,
                    value: @currency,
                    class: "flex w-32 items-center form-control text-base-250 border-none",
                    phx_debounce: "500",
                    maxlength: 3,
                    autocomplete: "off"
                  ) %>
                </dl>
                <dl>
                  <%= labeled_select(f, :type, [Check: :check, Cash: :cash],
                    label: "Payment type",
                    class: "w-full h-12 border rounded-lg"
                  ) %>
                </dl>
                <dl>
                  <dd>
                    <.date_picker_field
                      class="w-full h-12"
                      id="mark_as_paid_payment"
                      form={f}
                      field={:paid_at}
                      input_placeholder="mm/dd/yyyy"
                      input_label="Payment Date"
                    />
                  </dd>
                </dl>
              </div>
              <div class="flex justify-end items-center my-4 mr-5 gap-2">
                <button
                  class="button rounded-lg border border-blue-planning-300 py-1 px-7 bg-white hover:bg-blue-planning-100"
                  type="button"
                  title="cancel"
                  phx-click="select_add_payment"
                  phx-target={@myself}
                  phx-value-action="close"
                >
                  Cancel
                </button>
                <button
                  id="save-payment"
                  class="button rounded-lg border border-blue-planning-300 py-1 px-7 bg-white hover:bg-blue-planning-100 disabled:cursor-not-allowed disabled:bg-base-200"
                  type="submit"
                  phx-submit="save"
                  disabled={!@changeset.valid?}
                >
                  Save
                </button>
              </div>
            </.form>
          </div>
        <% end %>
        <div class="flex justify-end items-center mt-4 gap-8">
          <%= link to: ~p"/jobs/#{@proposal.job_id}/booking_proposals/#{@proposal.id}" do %>
            <button class="link block leading-5 text-black text-base">Download invoice</button>
          <% end %>
          <button
            id="done"
            class="rounded-md bg-black px-8 py-3 text-white"
            phx-click="close-modal"
            phx-target={@myself}
          >
            Done
          </button>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("close-modal", %{}, %{assigns: %{job: job}} = socket) do
    socket
    |> push_redirect(to: ~p"/jobs/#{job.id}")
    |> close_modal()
    |> noreply()
  end

  def handle_event(
        "validate",
        %{
          "payment_schedule" =>
            %{
              "paid_at" => paid_at,
              "price" => _,
              "type" => _
            } = params
        },
        %{assigns: %{current_user: current_user, currency: currency}} = socket
      ) do
    paid_at = date_to_datetime(paid_at, current_user.time_zone)

    params =
      params
      |> Currency.parse_params_for_currency({Money.Currency.symbol(currency), currency})
      |> Map.put("paid_at", paid_at)

    socket = assign_changeset(socket, params)

    owed = PaymentSchedules.owed_offline_price(socket.assigns.job)

    price =
      Ecto.Changeset.get_field(socket.assigns.changeset, :price) ||
        Money.new(0, currency)

    case Money.cmp(price, owed) do
      :gt ->
        socket.assigns.changeset
        |> Ecto.Changeset.add_error(:price, "must be within what remains")
        |> then(&assign(socket, :changeset, &1))

      _ ->
        socket
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        %{
          "payment_schedule" =>
            %{
              "paid_at" => paid_at,
              "price" => _,
              "type" => _
            } = params
        },
        %{
          assigns: %{
            add_payment_show: add_payment_show,
            job: %{payment_schedules: payment_schedules} = job,
            current_user: current_user,
            currency: currency
          }
        } = socket
      ) do
    pending_payments =
      Enum.filter(payment_schedules, &is_nil(&1.paid_at)) |> Enum.sort_by(& &1.due_at, :asc)

    due_at = pending_payments |> hd() |> Map.get(:due_at)
    paid_at = date_to_datetime(paid_at, current_user.time_zone)

    params =
      params
      |> Currency.parse_params_for_currency({Money.Currency.symbol(currency), currency})
      |> Map.put("due_at", due_at)
      |> Map.put("paid_at", paid_at)
      |> Map.put("job_id", job.id)
      |> Map.put("description", "Offline Payment")

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:new_payment, build_changeset(socket, params))
    |> Ecto.Multi.merge(fn %{new_payment: new_payment} ->
      pending_payments
      |> calculate_payment(new_payment, currency)
      |> update_or_delete_multi()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        socket
        |> assign(:add_payment_show, !add_payment_show)
        |> assign_payments()
        |> assign_job()
        |> send_offline_payment_email()

      {:error, _} ->
        socket
        |> put_flash(:error, "could not save payment_schedules.")
    end
    |> noreply()
  end

  def handle_event(
        "select_add_payment",
        _,
        %{
          assigns: %{
            add_payment_show: add_payment_show
          }
        } = socket
      ) do
    socket
    |> assign(:add_payment_show, !add_payment_show)
    |> noreply()
  end

  def handle_event("download-pdf", %{}, socket) do
    send(self(), :download_pdf)
    socket |> noreply()
  end

  @impl true
  defdelegate handle_event(name, params, socket), to: TodoplaceWeb.JobLive.Shared

  def build_changeset(%{}, params \\ %{}) do
    PaymentSchedule.add_payment_changeset(params)
  end

  defp date_to_datetime(paid_at, time_zone) do
    {:ok, datetime} = DateTime.now(time_zone)
    time = DateTime.to_time(datetime) |> Time.to_iso8601()
    "#{paid_at}T#{time}"
  end

  def assign_job(%{assigns: %{current_user: current_user, job: job}} = socket) do
    job =
      current_user
      |> Job.for_user()
      |> Job.not_leads()
      |> Ecto.Query.preload([:client, :package, :payment_schedules])
      |> Repo.get!(job.id)

    socket
    |> assign(:job, job)
  end

  def open(%{assigns: %{job: job, proposal: proposal}} = socket) do
    socket
    |> open_modal(__MODULE__, %{
      proposal: proposal,
      job: job,
      current_user: socket.assigns.current_user
    })
  end

  defp assign_currency(%{assigns: %{job: job}} = socket) do
    currency = Currency.for_job(job)

    socket
    |> assign(:currency_symbol, Money.Currency.symbol!(currency))
    |> assign(:currency, currency)
  end

  defp update_or_delete_multi({for_delete, for_update, _}) do
    multi = Ecto.Multi.new()
    multi = if for_update, do: Ecto.Multi.update(multi, :update_payment, for_update), else: multi

    if Enum.any?(for_delete),
      do:
        Ecto.Multi.delete_all(
          multi,
          :delete_payments,
          from(p in PaymentSchedule, where: p.id in ^for_delete)
        ),
      else: multi
  end

  defp assign_payments(%{assigns: %{job: job}} = socket) do
    payment_schedules = PaymentSchedules.get_offline_payment_schedules(job.id)
    socket |> assign(:payment_schedules, payment_schedules)
  end

  defp assign_changeset(socket, params) do
    changeset =
      socket
      |> build_changeset(params)
      |> Map.put(:action, :validate)

    assign(socket, changeset: changeset)
  end

  defp calculate_payment(pending_payments, new_payment, currency) do
    pending_payments
    |> Enum.reduce_while(
      {[], nil, Money.new(0, currency)},
      fn %{price: price} = payment, {for_delete, for_update, acc} ->
        owed = Money.add(price, acc)

        case Money.cmp(new_payment.price, owed) do
          :gt ->
            {:cont, {[payment.id | for_delete], for_update, owed}}

          :eq ->
            for_update =
              Ecto.Changeset.change(payment, price: Money.subtract(owed, new_payment.price))

            {:halt, {[payment.id | for_delete], for_update, owed}}

          _ ->
            for_update =
              Ecto.Changeset.change(payment, price: Money.subtract(owed, new_payment.price))

            {:halt, {for_delete, for_update, owed}}
        end
      end
    )
  end

  defp send_offline_payment_email(%{assigns: %{job: job, current_user: user}} = socket) do
    EmailAutomationSchedules.stopped_all_active_proposal_emails(job.id)
    EmailAutomations.send_pays_retainer(job, :pays_retainer_offline, user.organization_id)
    socket
  end
end
