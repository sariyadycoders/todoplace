defmodule TodoplaceWeb.ShootLive.EditComponent do
  @moduledoc false

  use TodoplaceWeb, :live_component

  import TodoplaceWeb.ShootLive.Shared,
    only: [duration_options: 0, location: 1, parse_shoot_time_zone: 2]

  import TodoplaceWeb.JobLive.Shared, only: [error: 1]
  import Ecto.Query, warn: false

  alias Todoplace.{
    Package,
    Packages,
    Shoot,
    Repo,
    PackagePaymentSchedule,
    PaymentSchedule,
    PackagePayments,
    Workers.CalendarEvent,
    EmailAutomation.EmailSchedule,
    EmailAutomationSchedules
  }

  alias Ecto.{Changeset, Multi}

  @impl true
  def update(%{job: job} = assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:address_field, fn ->
      match?(%{shoot: %{address: address}} when not is_nil(address), assigns)
    end)
    |> assign_changeset(%{}, nil)
    |> then(fn %{assigns: %{job: %{job_status: job_status}}} = socket ->
      if job_status.is_lead do
        socket
        |> assign(package_payment_schedules: preload_package_payment_schedules(job.package))
        |> assign(payment_schedules: preload_payment_schedules(job))
        |> assign(x_shoots: Shoot.for_job(job.id) |> Repo.all())
      else
        socket
      end
    end)
    |> ok()
  end

  @impl true
  def handle_event("address", %{"action" => "add-field"}, socket) do
    socket |> assign(address_field: true) |> noreply()
  end

  @impl true
  def handle_event(
        "place_changed",
        %{"formatted_address" => address},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    socket
    |> assign(:changeset, changeset |> Changeset.put_change(:address, address))
    |> noreply()
  end

  @impl true
  def handle_event(
        "address",
        %{"action" => "remove"},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    socket
    |> assign(
      address_field: false,
      changeset: Changeset.put_change(changeset, :address, nil)
    )
    |> noreply()
  end

  @impl true
  def handle_event("validate", %{"shoot" => params}, socket) do
    socket
    |> assign_changeset(params, :validate)
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        %{"shoot" => params},
        %{
          assigns: %{
            current_user: %{
              nylas_detail: %{
                oauth_token: oauth_token,
                external_calendar_rw_id: external_calendar_rw_id
              }
            },
            job: %{job_status: job_status} = job
          }
        } = socket
      ) do
    socket
    |> build_changeset(params |> Enum.into(%{"address" => nil}))
    |> then(fn changeset ->
      Multi.new()
      |> Multi.insert_or_update(:shoot, changeset)
      |> Multi.insert_all(:email_automation_job, EmailSchedule, fn %{shoot: shoot} ->
        EmailAutomationSchedules.shoot_emails(job, shoot)
      end)
      |> Multi.merge(fn
        %{shoot: shoot}
        when not is_nil(oauth_token) and not is_nil(external_calendar_rw_id) ->
          changeset
          |> params_for_event_job(shoot)
          |> CalendarEvent.new()
          |> then(&Oban.insert(Multi.new(), :event, &1))

        _ ->
          Multi.new()
      end)
      |> Multi.merge(fn _ ->
        if job_status.is_lead do
          {updated_package_payment_schedules, updated_payment_schedules,
           package_payment_schedule_ids, payment_schedule_ids} = get_schedules(socket)

          Multi.new()
          |> Ecto.Multi.delete_all(
            :delete_payments,
            from(p in PackagePaymentSchedule, where: p.id in ^package_payment_schedule_ids)
          )
          |> Ecto.Multi.delete_all(
            :delete_job_payments,
            from(p in PaymentSchedule, where: p.id in ^payment_schedule_ids)
          )
          |> Multi.insert_all(
            :package_payment_schedules,
            PackagePaymentSchedule,
            updated_package_payment_schedules,
            on_conflict: {:replace, [:schedule_date]},
            conflict_target: :id
          )
          |> Multi.insert_all(
            :job_payment_schedules,
            PaymentSchedule,
            updated_payment_schedules,
            on_conflict: {:replace, [:due_at]},
            conflict_target: :id
          )
        else
          Multi.new()
        end
      end)

      # here insert shoot emails for job
      |> Repo.transaction()
      |> then(fn
        {:ok, %{shoot: shoot}} ->
          send(
            self(),
            {:update, socket.assigns |> Map.take([:shoot_number]) |> Map.put(:shoot, shoot)}
          )

          Todoplace.Shoots.broadcast_shoot_change(shoot)

          socket |> assign(shoot: shoot) |> close_modal() |> noreply()

        {:error, _} ->
          socket |> assign(changeset: changeset) |> noreply()
      end)
    end)
  end

  defp params_for_event_job(changeset, shoot) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> case do
      %{id: nil} ->
        %{type: :insert, shoot_id: shoot.id}

      %{id: _id} ->
        %{type: :update, shoot_id: shoot.id}
    end
  end

  defp get_messgae(%{
         job: %{job_status: %{current_status: current_status}},
         shoot: shoot,
         changeset: changeset
       }) do
    cond do
      current_status not in [:not_sent, :imported] && Changeset.get_change(changeset, :starts_at) ->
        "Changing your shoot date after a proposal is sent or signed will result in your payment(s) being received at an earlier or later time depending on when you change it to."

      shoot && current_status != :imported && Changeset.get_change(changeset, :starts_at) ->
        "Changing your shoot date will mean you may need to update or review your payment schedule."

      true ->
        nil
    end
  end

  defp preload_package_payment_schedules(package) do
    package
    |> Repo.preload(:package_payment_schedules, force: true)
    |> Map.get(:package_payment_schedules)
  end

  defp preload_payment_schedules(job) do
    job |> Repo.preload(:payment_schedules, force: true) |> Map.get(:payment_schedules)
  end

  defp package_schedules_struct_map(schedules) do
    schedules
    |> Enum.map(
      &(&1
        |> Map.from_struct()
        |> Map.drop([
          :__meta__,
          :package,
          :package_payment_preset,
          :payment_field_index,
          :shoot_date,
          :fields_count,
          :last_shoot_date
        ]))
    )
  end

  defp payment_schedules_struct_map(schedules) do
    schedules |> Enum.map(&(&1 |> Map.from_struct() |> Map.drop([:__meta__, :job])))
  end

  defp get_schedules(%{
         assigns: %{
           x_shoots: x_shoots,
           job: job,
           payment_schedules: payment_schedules,
           package_payment_schedules: package_payment_schedules
         }
       }) do
    shoots = Shoot.for_job(job.id) |> Repo.all()
    {first_shoot_date, last_shoot_date} = get_fist_and_last_shoot_dates(shoots, :starts_at)

    if Enum.any?(payment_schedules) do
      get_schedules_for_update(
        x_shoots,
        payment_schedules,
        package_payment_schedules,
        first_shoot_date,
        last_shoot_date
      )
    else
      get_schedules_for_insert(job, package_payment_schedules, first_shoot_date, last_shoot_date)
    end
  end

  defp get_package_payment_schedules(
         package_payment_schedules,
         first_time_difference,
         last_time_difference
       ) do
    Enum.map(package_payment_schedules, fn schedule ->
      schedule_date =
        cond do
          schedule.interval && String.contains?(schedule.due_interval, "To Book") ->
            Timex.now()

          schedule.shoot_interval &&
              String.contains?(schedule.shoot_interval, "Before Last Shoot") ->
            Timex.shift(schedule.schedule_date, minutes: last_time_difference)

          schedule.due_at ->
            schedule.due_at |> Timex.to_datetime()

          true ->
            Timex.shift(schedule.schedule_date, minutes: first_time_difference)
        end
        |> DateTime.truncate(:second)

      Map.put(schedule, :schedule_date, schedule_date)
    end)
    |> package_schedules_struct_map()
  end

  defp get_schedules_for_insert(job, package_payment_schedules, first_shoot_date, last_shoot_date) do
    first_time_difference = get_diff(Packages.future_date(), first_shoot_date)
    last_time_difference = get_diff(Packages.future_date(), last_shoot_date)

    updated_package_payment_schedules =
      get_package_payment_schedules(
        package_payment_schedules,
        first_time_difference,
        last_time_difference
      )

    updated_job_payment_schedules =
      updated_package_payment_schedules
      |> PackagePayments.merge_payments()
      |> Enum.map(
        &%{
          job_id: job.id,
          type: "stripe",
          price: PackagePayments.get_price(&1, Package.price(job.package)),
          due_at: &1.schedule_date,
          description: &1.description,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      )

    package_payment_schedule_ids = Enum.map(updated_package_payment_schedules, & &1.id)

    updated_package_payment_schedules =
      PackagePayments.merge_payments(updated_package_payment_schedules)

    {updated_package_payment_schedules, updated_job_payment_schedules,
     package_payment_schedule_ids, []}
  end

  defp get_schedules_for_update(
         x_shoots,
         payment_schedules,
         package_payment_schedules,
         first_shoot_date,
         last_shoot_date
       ) do
    {x_first_shoot_date, x_last_shoot_date} = get_fist_and_last_shoot_dates(x_shoots, :starts_at)
    first_time_difference = get_diff(x_first_shoot_date, first_shoot_date)
    last_time_difference = get_diff(x_last_shoot_date, last_shoot_date)

    updated_package_payment_schedules =
      get_package_payment_schedules(
        package_payment_schedules,
        first_time_difference,
        last_time_difference
      )

    updated_payment_schedules =
      Enum.map(updated_package_payment_schedules, fn package_schedule ->
        find_and_map_payment_schedule(payment_schedules, package_schedule)
      end)
      |> List.flatten()
      |> payment_schedules_struct_map()

    package_payment_schedule_ids = Enum.map(updated_package_payment_schedules, & &1.id)
    payment_schedule_ids = Enum.map(updated_payment_schedules, & &1.id)

    updated_package_payment_schedules =
      PackagePayments.merge_payments(updated_package_payment_schedules)

    updated_payment_schedules = PackagePayments.merge_payments(updated_payment_schedules)

    {updated_package_payment_schedules, updated_payment_schedules, package_payment_schedule_ids,
     payment_schedule_ids}
  end

  defp find_and_map_payment_schedule(payment_schedules, package_schedule) do
    Enum.find_value(payment_schedules, [], fn %{description: description} = pyment_schedule ->
      pyment_schedule = Map.put(pyment_schedule, :type, "stripe")

      if description == package_schedule.description,
        do: Map.put(pyment_schedule, :due_at, package_schedule.schedule_date)
    end)
  end

  defp get_fist_and_last_shoot_dates(schedules, field) do
    {List.first(schedules) |> Map.get(field), List.last(schedules) |> Map.get(field)}
  end

  defp get_diff(date, x_date), do: Timex.diff(x_date, date, :minutes)

  defp build_changeset(
         %{assigns: %{current_user: %{time_zone: time_zone}}} = socket,
         %{"starts_at" => "" <> starts_at} = params
       ) do
    new_date = parse_shoot_time_zone(starts_at, time_zone)
    params = Map.put(params, "starts_at", new_date)
    build_changeset(socket, params)
  end

  defp build_changeset(%{assigns: %{shoot: shoot}}, params) when shoot != nil do
    shoot |> Shoot.update_changeset(params)
  end

  defp build_changeset(%{assigns: %{job: %{id: job_id}}}, params) do
    params
    |> Map.put("job_id", job_id)
    |> Shoot.changeset()
  end

  defp assign_changeset(
         socket,
         params,
         action
       ) do
    changeset = build_changeset(socket, params) |> Map.put(:action, action)
    assign(socket, changeset: changeset)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, message: get_messgae(assigns))

    ~H"""
    <div class="flex flex-col modal">
      <div class="flex items-start justify-between flex-shrink-0">
        <h1 class="mb-4 text-3xl font-bold">Edit Shoot Details</h1>

        <button
          phx-click="modal"
          phx-value-action="close"
          title="close modal"
          type="button"
          class="p-2"
        >
          <.icon name="close-x" class="w-3 h-3 stroke-current stroke-2 sm:stroke-1 sm:w-6 sm:h-6" />
        </button>
      </div>

      <.error
        message={@message}
        icon_class="w-6 h-6"
        class={classes(%{"md:hidden hidden" => is_nil(@shoot) || is_nil(@message)})}
      />

      <.form :let={f} for={@changeset} phx-change="validate" phx-submit="save" phx-target={@myself}>
        <div class="px-1.5 grid grid-cols-1 sm:grid-cols-6 gap-5">
          <%= labeled_input(f, :name,
            label: "Shoot Title",
            placeholder: "e.g. #{dyn_gettext(@job.type)} Session, etc.",
            wrapper_class: "sm:col-span-3"
          ) %>
          <.date_picker_field
            class="sm:col-span-3"
            id="shoot-time"
            placeholder="Select shoot time…"
            form={f}
            field={:starts_at}
            input_placeholder="mm/dd/yyyy"
            input_label="Shoot Date"
            data_custom_date_format="Y-m-d\\TH:i"
            data_time_picker="true"
            data_time_zone={@current_user.time_zone}
          />
          <%= labeled_select(f, :duration_minutes, duration_options(),
            label: "Shoot Duration",
            prompt: "Select below",
            wrapper_class:
              classes(%{"sm:col-span-3" => !@address_field, "sm:col-span-2" => @address_field})
          ) %>

          <.location f={f} address_field={@address_field} myself={@myself} />

          <%= labeled_input(f, :notes,
            type: :textarea,
            label: "Shoot Notes",
            placeholder: "e.g. Anything you'd like to remember",
            wrapper_class: "sm:col-span-6"
          ) %>
        </div>

        <TodoplaceWeb.LiveModal.footer disabled={!@changeset.valid?} />
      </.form>
    </div>
    """
  end
end
