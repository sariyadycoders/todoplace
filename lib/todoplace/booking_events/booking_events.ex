defmodule Todoplace.BookingEvents do
  @moduledoc "context module for booking events"
  alias Todoplace.{
    Repo,
    BookingEvent,
    Job,
    Package,
    BookingEventDate,
    BookingEventDates,
    EmailAutomations,
    EmailAutomationSchedules,
    ClientTag,
    PaymentSchedules,
    Jobs
  }

  alias Ecto.{Multi, Changeset}
  alias Todoplace.Workers.ExpireBooking
  import Ecto.Query

  defmodule Booking do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:name, :string)
      field(:email, :string)
      field(:phone, :string)
      field(:date, :date)
      field(:time, :time)
    end

    def changeset(attrs \\ %{}) do
      %__MODULE__{}
      |> cast(attrs, [:name, :email, :phone, :date, :time])
      |> validate_required([:name, :email, :phone, :date, :time])
    end
  end

  def create_booking_event(params) do
    %BookingEvent{}
    |> BookingEvent.changeset(params)
    |> Repo.insert()
  end

  def duplicate_booking_event(booking_event_id, organization_id) do
    booking_event_params =
      get_booking_event!(
        organization_id,
        booking_event_id
      )
      |> Repo.preload([:dates])
      |> Map.put(:status, :active)
      |> Map.from_struct()

    to_duplicate_booking_event =
      if String.contains?(booking_event_params.name, "duplicate-") do
        number =
          Regex.run(~r/-([0-9]+)/, booking_event_params.name)
          |> Enum.at(1)
          |> String.to_integer()

        new_number = number + 1

        name =
          String.replace(
            booking_event_params.name,
            "duplicate-#{number}",
            "duplicate-" <> "#{new_number}"
          )

        booking_event_params
        |> Map.merge(%{name: name})
      else
        booking_event_params
        |> Map.merge(%{name: booking_event_params.name <> " " <> "duplicate-1"})
      end

    to_duplicate_event_dates =
      to_duplicate_booking_event.dates
      |> Enum.map(fn t ->
        t
        |> Map.replace(:date, nil)
        |> Map.replace(:slots, BookingEventDates.transform_slots(t.slots))
      end)

    multi =
      Multi.new()
      |> Multi.insert(
        :duplicate_booking_event,
        BookingEvent.duplicate_changeset(to_duplicate_booking_event)
      )

    to_duplicate_event_dates
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {event_date, i}, multi ->
      multi
      |> Multi.insert(
        "duplicate_booking_event_date_#{i}",
        fn %{duplicate_booking_event: event} ->
          BookingEventDate.duplicate_changeset(%{
            booking_event_id: event.id,
            location: event_date.location,
            address: event_date.address,
            session_length: event_date.session_length,
            session_gap: event_date.session_gap,
            time_blocks: to_map(event_date.time_blocks),
            slots: to_map(event_date.slots)
          })
        end
      )
    end)
    |> Repo.transaction()
  end

  def upsert_booking_event(changeset) do
    changeset |> Repo.insert_or_update()
  end

  def get_all_booking_events(organization_id) do
    from(event in BookingEvent, where: event.organization_id == ^organization_id)
    |> Repo.all()
  end

  def sorted_booking_event(booking_event) do
    booking_event =
      booking_event
      |> Todoplace.Repo.preload([
        :dates,
        package_template: [:package_payment_schedules, :contract, :questionnaire_template]
      ])

    dates = reorder_time_blocks(booking_event.dates) |> Enum.sort_by(& &1.date, {:desc, Date})
    Map.put(booking_event, :dates, dates)
  end

  def get_booking_events_public(organization_id) do
    from(event in BookingEvent,
      join: package in assoc(event, :package_template),
      left_join: booking_date in assoc(event, :dates),
      where: package.organization_id == ^organization_id,
      where: event.status == :active,
      where: event.show_on_profile? == true,
      select: %{
        package_name: package.name,
        id: event.id,
        name: event.name,
        thumbnail_url: event.thumbnail_url,
        status: event.status,
        location: event.location,
        duration_minutes: event.duration_minutes,
        package_template: package,
        dates:
          fragment(
            "array_agg(to_jsonb(json_build_object('id', ?, 'booking_event_id', ?, 'date', ?, 'address', ?)))",
            booking_date.id,
            booking_date.booking_event_id,
            booking_date.date,
            booking_date.address
          ),
        description: event.description,
        address: event.address
      },
      group_by: [event.id, package.id, booking_date.booking_event_id]
    )
    |> Repo.all()
  end

  def get_booking_events(organization_id,
        filters: %{sort_by: sort_by, sort_direction: sort_direction} = opts
      ) do
    from(event in BookingEvent,
      left_join: job in assoc(event, :jobs),
      left_join: status in assoc(job, :job_status),
      left_join: package in assoc(event, :package_template),
      left_join: booking_date in assoc(event, :dates),
      where: event.organization_id == ^organization_id,
      where: ^filters_search(opts),
      where: ^filters_status(opts),
      select: %{
        booking_count: fragment("sum(case when ?.is_lead = false then 1 else 0 end)", status),
        can_edit?: fragment("count(?.*) = 0", job),
        package_template_id: event.package_template_id,
        package_name: package.name,
        id: event.id,
        name: event.name,
        thumbnail_url: event.thumbnail_url,
        status: event.status,
        dates:
          fragment(
            "array_agg(DISTINCT to_jsonb(json_build_object('id', ?, 'booking_event_id', ?, 'date', ?)))",
            booking_date.id,
            booking_date.booking_event_id,
            booking_date.date
          ),
        duration_minutes: event.duration_minutes,
        inserted_at: event.inserted_at,
        old_dates: event.old_dates
      },
      group_by: [event.id, package.name, booking_date.booking_event_id],
      order_by: ^filter_order_by(sort_by, sort_direction)
    )
    |> Repo.all()
    |> assign_booking_count()
  end

  defp filters_search(opts) do
    Enum.reduce(opts, dynamic(true), fn
      {:search_phrase, nil}, dynamic ->
        dynamic

      {:search_phrase, search_phrase}, dynamic ->
        search_phrase = "%#{search_phrase}%"

        dynamic(
          [client, jobs, job_status, package],
          ^dynamic and
            (ilike(client.name, ^search_phrase) or
               ilike(package.name, ^search_phrase))
        )

      {_, _}, dynamic ->
        # Not a where parameter
        dynamic
    end)
  end

  defp filters_status(opts) do
    Enum.reduce(opts, dynamic(true), fn
      {:status, value}, dynamic ->
        case value do
          "disabled_events" ->
            filter_disabled_events(dynamic)

          "archived_events" ->
            filter_archived_events(dynamic)

          _ ->
            remove_archive_events(dynamic)
        end

      _any, dynamic ->
        # Not a where parameter
        dynamic
    end)
  end

  defp remove_archive_events(dynamic) do
    dynamic(
      [client, jobs, job_status],
      ^dynamic and client.status != :archive
    )
  end

  defp filter_disabled_events(dynamic) do
    dynamic(
      [event],
      ^dynamic and event.status == :disabled
    )
  end

  defp filter_archived_events(dynamic) do
    dynamic(
      [client, jobs, job_status],
      ^dynamic and client.status == :archive
    )
  end

  # returned dynamic with join binding
  defp filter_order_by(:id, order),
    do: [{order, dynamic([client, event], count(field(event, :id)))}]

  defp filter_order_by(column, order) do
    column = update_column(column)
    [{order, dynamic([client], field(client, ^column))}]
  end

  def update_column(:date), do: :dates
  def update_column(column), do: column

  def get_booking_event_booked_slots(id) do
    BookingEventDates.get_booking_events_dates(id)
    |> Enum.flat_map(& &1.slots)
    |> Enum.count(fn slot -> slot.status == :booked end)
  end

  def get_booking_event!(organization_id, event_id) do
    from(event in BookingEvent, where: event.organization_id == ^organization_id)
    |> Repo.get!(event_id)
  end

  def get_booking_event_dates(event_id) do
    from(date in BookingEventDate, where: date.booking_event_id == ^event_id)
    |> Repo.all()
  end

  def get_preloaded_booking_event!(organization_id, event_id) do
    from(event in BookingEvent,
      join: package in assoc(event, :package_template),
      where: package.organization_id == ^organization_id,
      preload: [
        :dates,
        package_template: [:package_payment_schedules, :contract, :questionnaire_template]
      ]
    )
    |> Repo.get!(event_id)
  end

  def filter_booking_slots(%{date: nil, slots: slots}, _), do: slots

  def filter_booking_slots(
        %{
          slots: slot_times,
          date: date,
          session_length: duration_minutes,
          session_gap: buffer_minutes
        } = _booking_event_date,
        booking_event
      ) do
    %{organization: %{user: user} = organization} =
      booking_event
      |> Repo.preload(organization: :user)

    beginning_of_day = DateTime.new!(date, ~T[00:00:00], user.time_zone)

    end_of_day_with_buffer =
      DateTime.new!(date, ~T[23:59:59], user.time_zone)
      |> DateTime.add((Todoplace.Shoot.durations() |> Enum.max()) * 60)

    shoots = get_shoots(organization.id, beginning_of_day, end_of_day_with_buffer)

    slot_times
    |> Enum.map(fn slot_time ->
      slot_start = DateTime.new!(date, slot_time.slot_start, user.time_zone)
      previous_status = slot_time.status

      slot_end =
        slot_start
        |> DateTime.add(duration_minutes * 60)
        |> DateTime.add((buffer_minutes || 0) * 60 - 1)

      slot_status =
        get_latest_slot_status(
          slot_start,
          slot_end,
          buffer_minutes,
          previous_status,
          shoots,
          user.time_zone,
          booking_event
        )

      Map.merge(slot_time, slot_status)
    end)
  end

  def get_shoots_job_and_client(shoot) do
    shoot =
      shoot
      |> Repo.preload([:job])

    {shoot
     |> Map.get(:job_id),
     shoot
     |> Map.get(:job)
     |> Map.get(:client_id),
     shoot
     |> Map.get(:job)
     |> Map.get(:booking_event_id)}
  end

  @doc """
    saves a booking for a slot by creating its job, shoots, proposal, contract and updating the slot.
  """
  def save_booking(
        booking_event,
        booking_date,
        %{
          email: email,
          name: name,
          phone: phone,
          date: date,
          time: time
        },
        %{slot_index: slot_index, slot_status: slot_status}
      ) do
    %{package_template: %{organization: %{user: photographer}} = package_template} =
      booking_event
      |> Repo.preload(package_template: [organization: :user])

    starts_at = shoot_start_at(date, time, photographer.time_zone)

    Multi.new()
    |> Todoplace.Jobs.maybe_upsert_client(
      %Todoplace.Client{email: email, name: name, phone: phone},
      photographer
    )
    |> Multi.insert(:job, fn %{client: client} ->
      Todoplace.Job.changeset(%{
        type: package_template.job_type,
        client_id: client.id,
        is_reserved?: slot_status == :reserved
      })
      |> Changeset.put_change(:booking_event_id, booking_event.id)
    end)
    |> Multi.update(:booking_date_slot, fn %{client: client, job: job} ->
      BookingEventDate.update_slot_changeset(booking_date, slot_index, %{
        job_id: job.id,
        client_id: client.id,
        status: slot_status
      })
    end)
    |> Multi.merge(fn %{job: job} ->
      package_payment_schedules =
        package_template
        |> Repo.preload(:package_payment_schedules, force: true)
        |> Map.get(:package_payment_schedules)

      shoot_date = starts_at |> DateTime.shift_zone!("Etc/UTC")

      payment_schedules =
        package_payment_schedules
        |> Enum.map(fn schedule ->
          schedule
          |> Map.from_struct()
          |> Map.drop([:package_payment_preset_id])
          |> Map.put(:shoot_date, shoot_date)
          |> Map.put(:schedule_date, get_schedule_date(schedule, shoot_date))
        end)

      opts =
        if booking_event.include_questionnaire?,
          do: %{
            payment_schedules: payment_schedules,
            action: :insert,
            total_price: Package.price(package_template),
            questionnaire: Todoplace.Questionnaire.for_package(package_template)
          },
          else: %{
            payment_schedules: payment_schedules,
            action: :insert,
            total_price: Package.price(package_template)
          }

      package_template
      |> Map.put(:is_template, false)
      |> Todoplace.Packages.changeset_from_template()
      |> Todoplace.Packages.insert_package_and_update_job(job, opts)
    end)
    |> Multi.merge(fn %{package: package} ->
      Todoplace.Contracts.maybe_add_default_contract_to_package_multi(package)
    end)
    |> Multi.insert(:shoot, fn %{job: job} ->
      Todoplace.Shoot.create_booking_event_shoot_changeset(
        booking_event
        |> Map.take([:name])
        |> Map.put(:starts_at, starts_at)
        |> Map.put(:job_id, job.id)
        |> Map.put(:duration_minutes, booking_date.session_length)
        |> Map.put(:address, booking_date.address)
      )
    end)
    |> Ecto.Multi.insert(:proposal, fn %{job: job, package: package} ->
      questionnaire_id =
        if booking_event.include_questionnaire?,
          do: package.questionnaire_template_id,
          else: nil

      Todoplace.BookingProposal.changeset(%{
        job_id: job.id,
        questionnaire_id: questionnaire_id
      })
    end)
    |> then(fn
      multi when slot_status == :booked ->
        Oban.insert(multi, :oban_job, fn %{job: job} ->
          # multiply booking reservation by 2 to account for time spent on Stripe checkout
          expiration = Application.get_env(:todoplace, :booking_reservation_seconds) * 2

          ExpireBooking.new(
            %{id: job.id, booking_date_id: booking_date.id, slot_index: slot_index},
            schedule_in: expiration
          )
        end)

      multi ->
        multi
    end)
    |> Repo.transaction()
  end

  def reschedule_booking(
        old_booking_event_date,
        new_booking_event_date,
        %{old_slot_index: old_slot_index, slot_index: new_slot_index, slot_status: slot_status}
      ) do
    old_slots = Enum.at(old_booking_event_date.slots, old_slot_index)
    job_from_old_slots = old_slots |> Map.get(:job) |> Repo.preload([:shoots, :booking_proposals])
    client_from_old_slots = Map.get(old_slots, :client)

    BookingEventDates.update_slot_status(old_booking_event_date.id, old_slot_index, %{
      job: nil,
      job_id: nil,
      client: nil,
      client_id: nil,
      status: :open
    })

    if slot_status == :booked do
      expiration =
        get_previous_expiration_date(
          job_from_old_slots.id,
          old_slot_index,
          old_booking_event_date
        )

      if not is_nil(expiration) and Timex.after?(expiration, Timex.now()) do
        Oban.insert(
          ExpireBooking.new(
            %{
              id: job_from_old_slots.id,
              booking_date_id: new_booking_event_date.id,
              slot_index: new_slot_index
            },
            scheduled_at: expiration
          )
        )
      end
    end

    BookingEventDates.update_slot_status(new_booking_event_date.id, new_slot_index, %{
      job: job_from_old_slots,
      job_id: job_from_old_slots.id,
      client: client_from_old_slots,
      client_id: client_from_old_slots.id,
      status: slot_status
    })
  end

  @doc "expires a booking on a specific slot by expiring its job and updating the slot status to :open"
  def expire_booking(%{
        "id" => job_id,
        "booking_date_id" => booking_date_id,
        "slot_index" => slot_index
      }) do
    job = Jobs.get_job_by_id(job_id)

    if !PaymentSchedules.paid_any?(job) and !PaymentSchedules.is_with_cash?(job) do
      make_the_booking_expired(%{
        "id" => job_id,
        "booking_date_id" => booking_date_id,
        "slot_index" => slot_index
      })
    else
      :discard
    end
  end

  def make_the_booking_expired(%{
        "id" => job_id,
        "booking_date_id" => booking_date_id,
        "slot_index" => slot_index
      }) do
    {:ok, job} =
      Job
      |> Repo.get(job_id)
      |> expire_booking_job()

    {:ok, _} = Jobs.archive_job(job)

    {:ok, _} =
      BookingEventDates.update_slot_status(booking_date_id, slot_index, %{
        job_id: nil,
        client_id: nil,
        status: :open
      })
  end

  def disable_booking_event(event_id, organization_id) do
    get_booking_event!(organization_id, event_id)
    |> BookingEvent.disable_changeset()
    |> Repo.update()
  end

  def archive_booking_event(event_id, organization_id) do
    get_booking_event!(organization_id, event_id)
    |> BookingEvent.archive_changeset()
    |> Repo.update()
  end

  def enable_booking_event(event_id, organization_id) do
    get_booking_event!(organization_id, event_id)
    |> BookingEvent.enable_changeset()
    |> Repo.update()
  end

  @doc "expires a job created for a booking"
  def expire_booking_job(%Job{} = job) do
    with %Job{
           job_status: job_status,
           client: %{organization: organization} = client,
           payment_schedules: payment_schedules
         } <-
           job |> Repo.preload([:payment_schedules, :job_status, client: :organization]),
         %Todoplace.JobStatus{is_lead: true} <- job_status,
         {:ok, _} <-
           EmailAutomationSchedules.insert_job_emails(
             job.type,
             organization.id,
             job.id,
             :lead,
             [
               :client_contact
             ]
           ),
         _email_sent <- send_abandoned_email(job, organization),
         {:ok, _} <- Todoplace.Jobs.archive_job(job),
         {:ok, _} <- update_client_struct(client) do
      for %{stripe_session_id: "" <> session_id} <- payment_schedules,
          do:
            {:ok, _} =
              Todoplace.Payments.expire_session(session_id,
                connect_account: organization.stripe_account_id
              )

      {:ok, job}
    else
      %Todoplace.JobStatus{is_lead: false} -> {:ok, job}
      {:error, error} -> {:error, error}
    end
  end

  def preload_booking_event(event),
    do:
      Repo.preload(event,
        dates:
          from(d in BookingEventDate,
            where: d.booking_event_id == ^event.id,
            order_by: d.date,
            preload: [slots: [:client, :job]]
          ),
        package_template: [:package_payment_schedules, :contract, :questionnaire_template]
      )

  @spec overlap_time?(blocks :: [map]) :: boolean
  def overlap_time?(blocks) do
    for(
      [%{end_time: %Time{} = previous_time}, %{start_time: %Time{} = start_time}] <-
        Enum.chunk_every(blocks, 2, 1),
      do: Time.compare(previous_time, start_time) == :gt
    )
    |> Enum.any?()
  end

  @spec to_map(data :: [struct()]) :: [map()]
  def to_map(data), do: Enum.map(data, &Map.from_struct(&1))

  @spec calculate_repeat_dates(map(), [map()]) :: [any()]
  def calculate_repeat_dates(booking_event_date, selected_days) do
    selected_days = selected_days_indexed_array(selected_days)
    booking_date = Map.get(booking_event_date, :date)
    calendar = Map.get(booking_event_date, :calendar)
    repeat_interval = Map.get(booking_event_date, :count_calendar)
    shift_date = calendar_shift(calendar, repeat_interval * -1, booking_date)

    calculate_repeat_dates(
      booking_date,
      shift_date,
      Map.get(booking_event_date, :stop_repeating),
      Map.get(booking_event_date, :occurrences),
      calendar,
      repeat_interval,
      selected_days,
      []
    )
  end

  defp calculate_repeat_dates(
         _booking_date,
         _shift_date,
         _stopped_date,
         _occurrences,
         calendar,
         _repeat_interval,
         selected_days,
         _acc_dates
       )
       when selected_days == [] or calendar in ["", nil] do
    []
  end

  # Recursively calculates a list of dates based on specified criteria.
  defp calculate_repeat_dates(
         booking_date,
         shift_date,
         stopped_date,
         occurrences,
         calendar,
         repeat_interval,
         selected_days,
         acc_dates
       )
       when selected_days != [] do
    recursive_cond? =
      if occurrences > 0,
        do: Enum.count(acc_dates) < occurrences,
        else: date_valid?(shift_date, stopped_date)

    if recursive_cond? do
      shifted_date = calendar_shift(calendar, repeat_interval, shift_date)

      dates =
        calculate_week_day_date(
          acc_dates,
          booking_date,
          shifted_date,
          occurrences,
          stopped_date,
          selected_days
        )

      calculate_repeat_dates(
        booking_date,
        shifted_date,
        stopped_date,
        occurrences,
        calendar,
        repeat_interval,
        selected_days,
        dates
      )
    else
      Enum.reverse(acc_dates) |> Enum.sort()
    end
  end

  # Calculates dates based on specified weekdays, within certain criteria.
  defp calculate_week_day_date(
         dates,
         booking_date,
         shifted_date,
         occurrences,
         stopped_date,
         selected_days
       ) do
    shifted_date = Timex.shift(shifted_date, days: -1)

    Enum.reduce_while(1..7, dates, fn n, acc ->
      next_day = Timex.shift(shifted_date, days: n)
      weekday = day_of_week(next_day)

      halt_condition =
        if occurrences > 0,
          do: Enum.count(acc) >= occurrences,
          else: !date_valid?(next_day, stopped_date)

      cond do
        halt_condition -> {:halt, acc}
        booking_date == next_day -> {:cont, acc}
        weekday in selected_days -> {:cont, acc ++ [next_day]}
        true -> {:cont, acc}
      end
    end)
  end

  # Calculates the day of the week for a given date.
  defp day_of_week(date), do: Timex.weekday(date, :sunday)

  defp date_valid?(%Date{} = date, %Date{} = stopped_date),
    do: Date.compare(date, stopped_date) == :lt

  defp date_valid?(_date, _stopped_date), do: false

  # Generates an indexed array of selected days.
  defp selected_days_indexed_array(selected_days) do
    selected_days
    |> Enum.with_index()
    |> Enum.reduce([], fn {row, index}, acc ->
      if row.active, do: [{row, index} | acc], else: acc
    end)
    |> Enum.map(fn {_map, value} -> value + 1 end)
  end

  # Shifts a date by a specified amount based on the calendar unit.
  defp calendar_shift(nil, _shift_count, date), do: date
  defp calendar_shift("", shift_count, date) when shift_count in [-1, 1, nil], do: date
  defp calendar_shift("week", shift_count, date), do: Timex.shift(date, weeks: shift_count)
  defp calendar_shift("month", shift_count, date), do: Timex.shift(date, months: shift_count)
  defp calendar_shift("year", shift_count, date), do: Timex.shift(date, years: shift_count)

  defp reorder_time_blocks(dates) do
    Enum.map(dates, fn %{time_blocks: time_blocks} = event_date ->
      sorted_time_blocks = Enum.sort_by(time_blocks, &{&1.start_time, &1.end_time})
      %{event_date | time_blocks: sorted_time_blocks}
    end)
  end

  defp send_abandoned_email(job, organization) do
    if is_nil(job.archived_at),
      do: EmailAutomations.send_email_by_state(job, :abandoned_emails, organization.id, :lead)
  end

  defp update_client_struct(client) do
    tag =
      from(t in ClientTag, where: t.name == "Expired Booking" and t.client_id == ^client.id)
      |> Repo.one()

    if is_nil(tag) do
      ClientTag.changeset(%{
        "name" => "Expired Booking",
        "client_id" => client.id
      })
      |> Repo.insert()
    else
      {:ok, :no_insertion_required}
    end
  end

  defp get_previous_expiration_date(job_id, old_slot_index, old_booking_event_date) do
    from(j in Todoplace.Schema.Oban,
      where:
        fragment("? ->> 'booking_date_id' = ?", j.args, ^to_string(old_booking_event_date.id)),
      where: fragment("? ->> 'id' = ?", j.args, ^to_string(job_id)),
      where: fragment("? ->> 'slot_index' = ?", j.args, ^to_string(old_slot_index)),
      select: j.scheduled_at
    )
    |> Repo.one()
  end

  defp get_schedule_date(schedule, shoot_date) do
    case schedule.interval do
      true ->
        transform_text_to_date(schedule.due_interval, shoot_date)

      _ ->
        transform_text_to_date(schedule, shoot_date)
    end
  end

  defp transform_text_to_date(%{} = schedule, shoot_date) do
    due_at = schedule.due_at

    if due_at || schedule.shoot_date do
      if due_at, do: due_at |> Timex.to_datetime(), else: shoot_date
    else
      last_shoot_date = shoot_date
      count_interval = schedule.count_interval
      count_interval = if count_interval, do: count_interval |> String.to_integer(), else: 1
      time_interval = schedule.time_interval

      time_interval =
        if(time_interval, do: time_interval <> "s", else: "Days")
        |> String.downcase()
        |> String.to_atom()

      if(schedule.shoot_interval == "Before 1st Shoot",
        do: Timex.shift(shoot_date, [{time_interval, -count_interval}]),
        else: Timex.shift(last_shoot_date, [{time_interval, -count_interval}])
      )
    end
  end

  defp transform_text_to_date("" <> due_interval, shoot_date) do
    cond do
      String.contains?(due_interval, "6 Months Before") ->
        Timex.shift(shoot_date, months: -6)

      String.contains?(due_interval, "1 Month Before") ->
        Timex.shift(shoot_date, months: -1)

      String.contains?(due_interval, "Week Before") ->
        Timex.shift(shoot_date, days: -7)

      String.contains?(due_interval, "Day Before") ->
        Timex.shift(shoot_date, days: -1)

      String.contains?(due_interval, "To Book") ->
        DateTime.utc_now() |> DateTime.truncate(:second)

      true ->
        shoot_date
    end
  end

  defp is_slot_booked?(nil, slot_start, slot_end, start_time, end_time) do
    (DateTime.compare(slot_start, start_time) in [:gt, :eq] &&
       DateTime.compare(slot_start, end_time) == :lt) ||
      (DateTime.compare(slot_end, start_time) in [:gt, :eq] &&
         DateTime.compare(slot_end, end_time) == :lt) ||
      slot_overlap?(slot_start, slot_end, start_time, end_time)
  end

  defp is_slot_booked?(_buffer, slot_start, slot_end, start_time, end_time) do
    (DateTime.compare(slot_start, start_time) in [:gt, :eq] &&
       DateTime.compare(slot_start, end_time) in [:lt, :eq]) ||
      (DateTime.compare(slot_end, start_time) in [:gt, :eq] &&
         DateTime.compare(slot_end, end_time) in [:lt, :eq]) ||
      slot_overlap?(slot_start, slot_end, start_time, end_time)
  end

  defp slot_overlap?(slot_start, slot_end, start_time, end_time) do
    (DateTime.compare(start_time, slot_start) in [:gt] &&
       DateTime.compare(start_time, slot_end) == :lt) ||
      (DateTime.compare(end_time, slot_start) in [:gt] &&
         DateTime.compare(end_time, slot_end) == :lt)
  end

  defp assign_booking_count(events) do
    Enum.map(events, fn event ->
      Map.put(event, :booking_count, get_booking_event_booked_slots(event.id))
    end)
  end

  defp get_shoots(organization_id, beginning_of_day, end_of_day_with_buffer) do
    from(shoot in Todoplace.Shoot,
      join: job in assoc(shoot, :job),
      join: client in assoc(job, :client),
      where:
        client.organization_id == ^organization_id and is_nil(job.archived_at) and
          is_nil(job.completed_at),
      where: shoot.starts_at >= ^beginning_of_day and shoot.starts_at <= ^end_of_day_with_buffer
    )
    |> Repo.all()
  end

  defp get_latest_slot_status(
         slot_start,
         slot_end,
         buffer_minutes,
         previous_status,
         shoots,
         time_zone,
         booking_event
       ) do
    Enum.reduce_while(shoots, %{}, fn shoot, _acc ->
      start_time = shoot.starts_at |> DateTime.shift_zone!(time_zone)

      end_time =
        shoot.starts_at
        |> DateTime.add(shoot.duration_minutes * 60)
        |> DateTime.shift_zone!(time_zone)

      booked =
        is_slot_booked?(
          buffer_minutes,
          slot_start,
          slot_end,
          start_time,
          end_time
        )

      {job_id, client_id, booking_event_id} = get_shoots_job_and_client(shoot)
      status = if booking_event_id == booking_event.id, do: :booked, else: :break

      new_status =
        cond do
          previous_status == :reserved and booked -> :reserved
          status == :booked and booked -> :booked
          status == :break and booked -> :break
          true -> previous_status
        end

      if booked do
        {:halt, %{status: new_status, job_id: job_id, client_id: client_id}}
      else
        {:cont, %{status: new_status, job_id: nil, client_id: nil}}
      end
    end)
  end

  defp shoot_start_at(date, time, time_zone), do: DateTime.new!(date, time, time_zone)
end
