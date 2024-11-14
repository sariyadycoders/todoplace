defmodule TodoplaceWeb.Live.Calendar.BookingEventModal do
  @moduledoc false
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.ShootLive.Shared, only: [duration_options: 0, location: 1]
  import TodoplaceWeb.LiveModal, only: [close_x: 1, footer: 1]
  import TodoplaceWeb.PackageLive.Shared, only: [current: 1]
  import Ecto.Changeset

  import TodoplaceWeb.Calendar.BookingEvents.Shared,
    only: [
      check_external_slot_booked: 4,
      check_any_slot_booked_externally: 4,
      remove_conflicting_slots: 4,
      to_datetime: 2,
      is_changeset: 1
    ]

  alias Todoplace.{BookingEvents, BookingEventDate, BookingEventDates, NylasCalendar, Repo}
  alias TodoplaceWeb.Calendar.BookingEvents.Shared
  alias Ecto.Multi

  @occurrences [0, 5, 10, 15, 20, 30, 45, 60]

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:open_slots, 0)
    |> assign(:external_calendar_events, [])
    |> case do
      %{
        assigns: %{
          booking_date: %BookingEventDate{id: nil, session_length: nil},
          booking_event: booking_event
        }
      } = socket ->
        socket
        |> assign_changeset(%{
          "time_blocks" => [%{}],
          "slots" => [],
          "is_repeat" => booking_event.is_repeating
        })

      %{
        assigns: %{
          booking_event: booking_event,
          booking_date: booking_date,
          current_user: %{nylas_detail: nylas_detail, time_zone: time_zone}
        }
      } = socket ->
        socket
        |> assign_changeset(%{
          "is_repeat" =>
            booking_event.is_repeating && booking_date.calendar in ["week", "month", "year"]
        })
        |> assign(
          :external_calendar_events,
          get_external_events(nylas_detail, booking_date, time_zone)
        )
    end
    |> then(fn %{assigns: %{booking_date: %{date: date, booking_event_id: booking_event_id}}} =
                 socket ->
      socket
      |> assign(
        :has_booking?,
        if(date,
          do: BookingEventDates.is_booked_any_date?([date], booking_event_id),
          else: false
        )
      )
    end)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal">
      <.close_x />
      <div class="text-4xl font-bold"><%= @title %></div>
      <div class="mt-4 gap-5">
        <div>
          <div class="text-blue-planning-300 bg-blue-planning-100 w-14 h-6 pt-0.5 text-center font-bold text-sm rounded-lg">Note</div>
          <p>Sessions blocks that are booked, in the process of booking, or reserved are locked. They will not adjust when making changes to any of your date settings.</p>
        </div>
      </div>

      <.form :let={f} for={@changeset} phx-change="validate" phx-submit="submit" phx-target={@myself} >
        <div class="mt-4 px-4 border rounded-lg border-base-200" >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
            <.date_picker_field id="test-id" class="w-full cursor-text" form={f} field={:date} input_placeholder="mm/dd/yyyy" input_label="Event Date" data_min_date={Date.utc_today()} disabled={@has_booking?} />
          <%= inputs_for f, :time_blocks, fn t -> %>
            <div class="flex gap-2 items-center">
              <div class="grow">
                <%= labeled_input t, :start_time, type: :time_input, label: "Event Start", class: "cursor-text", disabled: @has_booking? %>
              </div>
              <div class="pt-5"> - </div>
              <div class="grow">
                <%= labeled_input t, :end_time, type: :time_input, label: "Event End", class: "cursor-text" , disabled: @has_booking?%>
              </div>
            </div>
          <% end %>
          <div>
            <.location f={f} myself={@myself} allow_location_toggle={false} allow_address_toggle={false} address_field={true} is_edit={!@has_booking?} address_field_title="Event Address" />
          </div>
          <div class="flex gap-5">
            <div class="grow">
              <%= labeled_select f, :session_length, duration_options(), label: "Session length", prompt: "Select below", disabled: @has_booking?, class: "cursor-pointer"%>
            </div>
            <div class="grow">
              <%= labeled_select f, :session_gap, buffer_options(), label: "Session Gap", prompt: "Select below", optional: true, disabled: @has_booking?, class: "cursor-pointer" %>
            </div>
          </div>
          </div>
          <div class="flex justify-center mr-16">
            <%= error_tag(f, :time_blocks, prefix: "Times", class: "text-red-sales-300 text-sm mb-2") %>
          </div>

          <div class="mt-6 flex items-center">
          <%= input f, :is_repeat, type: :checkbox, class: "checkbox border-blue-planning-300 w-6 h-6 cursor-pointer" %>
          <div class="ml-2">
            Repeat dates?
          </div>
          </div>
          <%= if @changeset |> current |> Map.get(:is_repeat) do %>
          <div class="lg:w-2/3 border-2 border-base-200 rounded-lg mt-4">
            <div class="font-bold p-4 bg-base-200 text-md">
              Repeat settings
            </div>
            <div class="grid grid-cols-1 md:grid-cols-5 gap-3 p-4">
              <div class="md:col-span-3">
                <div class="font-bold mb-1">Repeat every:</div>
                <div class="flex gap-4 items-center w-full">
                  <%= input f, :count_calendar, placeholder: 1, class: "w-24 bg-white p-3 focus:ring-0 focus:outline-none border-2 focus:border-blue-planning-300 text-lg sm:mt-0 font-normal text-center"%>
                  <%= select f, :calendar, ["week", "month", "year"], class: "w-28 select cursor-pointer"%>
                </div>
                <div>
                  <%= error_tag(f, :count_calendar, class: "text-red-sales-300 text-sm mb-2") %>
                </div>
                <div class="mt-5 font-bold mb-1">Repeat on:</div>
                <div class="flex gap-6 font-bold">
                <%= inputs_for f, :repeat_on, fn r -> %>
                  <div class="flex flex-col items-center">
                    <div>
                      <%= input r, :active, type: :checkbox, class: "checkbox  border-blue-planning-300 w-6 h-6 cursor-pointer" %>
                      <%= hidden_input r, :day, value: input_value(r, :day) %>
                    </div>
                    <div class="text-blue-planning-300">
                      <%= input_value(r, :day) %>
                    </div>
                   </div>
                <% end %>
                </div>
              </div>
              <div class="md:col-span-2">
                <div class="font-bold mb-2 mt-2 md:mt-0">Stop repeating:</div>
                <div class="flex gap-5 mb-2"><%= radio_button f, :repetition, false, class: "w-5 h-5 radio cursor-pointer mb-1" %> On</div>
                <div class={classes("pl-10 mb-2", %{"pointer-events-none text-base-250" => input_value(f, :repetition) === true})}>
                  <%= input f, :stop_repeating, type: :date_input, disabled: is_nil(@changeset |> current |> Map.get(:date)), min: min_date_stop_repeating(@changeset), class: "w-40" %>
                </div>
                <div><%= error_tag(f, :stop_repeating, class: "text-red-sales-300 text-sm mb-2") %></div>
                <div class="flex gap-5 mb-2"><%= radio_button f, :repetition, true, class: "w-5 h-5 radio cursor-pointer mb-2" %>After</div>
                <div class={classes("pl-10 mb-2", %{"pointer-events-none text-base-250" => input_value(f, :repetition) != true})}>
                  <%= select f, :occurrences, occurence_options(), class: "select w-40 cursor-pointer" %>
                </div>
                <div><%= error_tag(f, :occurrences, class: "text-red-sales-300 text-sm mb-2") %></div>
              </div>
            </div>
          </div>
          <% end %>
          <hr class="mt-4">
          <% date = @changeset |> current |> Map.get(:date) %>
          <% open_slots = remove_conflicting_slots(input_value(f, :slots), date, @external_calendar_events, @current_user.time_zone) |> Enum.reject(fn changeset ->  Map.get(changeset, :action) == :replace end) |>  Enum.count(fn slot_changeset -> is_changeset(slot_changeset) |> Map.get(:status) == :open end)%>
          <div class="font-bold mt-4">You'll have <span class="text-blue-planning-300"><%= open_slots %></span> open session blocks</div>
          <hr class="mt-4">
          <% slots = f |> current |> Map.get(:slots) %>
          <%= if check_any_slot_booked_externally(slots, date, @external_calendar_events, @current_user.time_zone) do %>
            <div>
              <div class="text-blue-planning-300 bg-blue-planning-100 mt-2 w-14 h-6 pt-0.5 text-center font-bold text-sm rounded-lg">Note</div>
              <p class="ml-2">Your calendar has existing sessions, booking events and/or conflicts with some of the dates and times. Those conflicts will show as “Unavailable” from this booking event. Review your calendar for additional details.</p>
            </div>
            <hr class="mt-4">
          <% end %>
          <div class="my-6 grid grid-cols-5 border-b-4 border-blue-planning-300 text-lg font-bold">
          <div class="col-span-2">Time</div>
          <div class="col-span-3">Status</div>
          </div>
          <% slots_length = input_value(f, :slots) |> Enum.count() %>
          <%= for {s, index} <- Enum.with_index(inputs_for(f, :slots)) do %>
           <% external_booked? = check_external_slot_booked(current(s), date, @external_calendar_events, @current_user.time_zone) %>
          <div class="mt-4 grid grid-cols-5 items-center">
            <div class={classes("col-span-2", %{"text-base-250" => (slot_status(s) |> to_string() == "hidden" || external_booked? || slot_already_booked?(s) )})}>
              <%= hidden_input s, :slot_start %>
              <%= hidden_input s, :slot_end %>

              <%= Shared.parse_time(input_value(s, :slot_start)) <> "-" <> Shared.parse_time(input_value(s, :slot_end))%> <%= get_buffer_text(input_value(f, :session_gap), input_value(f, :session_length), input_value(s, :slot_start), get_event_time(@changeset), index, slots_length) %>
              </div>
              <div>
                <%= cond do %>
                  <% slot_status(s) |> to_string() == "hidden" -> %>
                    <div class="text-base-250" > Booked (Hidden) </div>
                  <% external_booked? || slot_already_booked?(s) -> %>
                    <div class="text-base-250" > Unavailable </div>
                  <% true -> %>
                    <%= slot_status(s) |> to_string() |> String.capitalize() %>
                <% end %>
              </div>
              <div class="col-span-2 flex justify-end pr-2">
                <%= unless slot_status(s) in  [:booked, :reserved] do %>
                  <%= input s, :is_hide, type: :checkbox, checked: hidden_time?(slot_status(s)) || external_booked? || slot_already_booked?(s), disabled: external_booked? || slot_already_booked?(s), class: "checkbox w-6 h-6 cursor-pointer border-blue-planning-300"%>
                  <div class="ml-2"> Show block as booked (break)</div>
                <% end %>
              </div>
              <%= hidden_input s, :client_id, value: s |> current |> Map.get(:client_id) %>
              <%= hidden_input s, :job_id, value: s |> current |> Map.get(:job_id) %>
              <%= hidden_input s, :status, value: slot_status(s) %>
              <%= hidden_input s, :is_already_booked, value: slot_already_booked?(s) %>
            </div>
          <hr class="mt-4">
          <% end %>
        </div>
        <.footer class="pt-16">
          <button class="btn-primary" title="Save" type="submit" disabled={!@changeset.valid? || Enum.empty?(@changeset.changes)} phx-disable-with="Save">
              Save
          </button>
          <button class="btn-secondary" title="cancel" type="button" phx-click="modal" phx-value-action="close">
              Cancel
          </button>
        </.footer>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event(
        "place_changed",
        %{"formatted_address" => address},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    socket
    |> assign(:changeset, changeset |> Ecto.Changeset.put_change(:address, address))
    |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "booking_event_date" => params,
          "_target" => ["booking_event_date", "slots", _, "is_hide"]
        },
        socket
      ) do
    socket |> assign_changeset(params, :validate) |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "booking_event_date" => params,
          "_target" => ["booking_event_date", "date"]
        },
        %{
          assigns: %{
            booking_date: %BookingEventDate{session_length: session_length}
          }
        } = socket
      )
      when not is_nil(session_length) do
    socket
    |> assign_changeset_with_existing_slots(params)
    |> noreply()
  end

  @impl true
  def handle_event("validate", %{"booking_event_date" => params, "_target" => target}, socket) do
    if Map.has_key?(params, "slots") and
         target not in [
           ["booking_event_date", "session_gap"],
           ["booking_event_date", "session_length"],
           ["booking_event_date", "time_blocks", "0", "start_time"],
           ["booking_event_date", "time_blocks", "0", "end_time"]
         ] do
      socket |> assign_changeset_with_existing_slots(params, :validate)
    else
      socket |> assign_changeset_with_slots(params, :validate)
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "submit",
        %{"booking_event_date" => _params},
        %{assigns: %{changeset: changeset, booking_date: booking_date}} = socket
      ) do
    changeset = changeset |> Map.replace(:action, nil)

    %{dates: repeat_dates, params: repeat_dates_rows} =
      if get_field(changeset, :is_repeat) do
        repeat_dates = get_repeat_dates(changeset)

        is_booked_dates =
          BookingEventDates.is_booked_any_date?(repeat_dates, booking_date.booking_event_id)

        if is_booked_dates,
          do: %{dates: [], params: []},
          else: %{
            dates: repeat_dates,
            params: BookingEventDates.generate_rows_for_repeat_dates(changeset, repeat_dates)
          }
      else
        %{dates: [], params: []}
      end

    {:ok,
     %{
       upsert_booking_event_date: booking_event_date
     }} =
      Multi.new()
      |> Multi.insert_or_update(:upsert_booking_event_date, changeset)
      |> Multi.delete_all(
        :delete_all_repeating_dates,
        BookingEventDates.repeat_dates_queryable(repeat_dates, booking_date.booking_event_id)
      )
      |> Multi.insert_all(
        :insert_all_repeating_booking_dates,
        BookingEventDate,
        repeat_dates_rows
      )
      |> Repo.transaction()

    socket
    |> successfull_save(booking_event_date)
  end

  defp get_repeat_dates(changeset) do
    selected_days = get_field(changeset, :repeat_on) |> Enum.map(&Map.from_struct(&1))
    booking_event_date = current(changeset)
    BookingEvents.calculate_repeat_dates(booking_event_date, selected_days)
  end

  defp min_date_stop_repeating(changeset) do
    if get_field(changeset, :date) && get_field(changeset, :calendar) do
      selected_days = get_field(changeset, :repeat_on) |> Enum.map(&Map.from_struct(&1))
      selected_days_no = selected_days |> Enum.filter(& &1.active) |> length()

      booking_event_date =
        changeset
        |> current()
        |> Map.put(:occurrences, selected_days_no)

      BookingEvents.calculate_repeat_dates(booking_event_date, selected_days)
      |> List.first()
    end
  end

  defp successfull_save(socket, booking_event_date) do
    send(self(), {:update, %{booking_event_date: booking_event_date}})

    socket
    |> close_modal()
    |> noreply()
  end

  defp buffer_options() do
    for(
      duration <- [5, 10, 15, 20, 30, 45, 60],
      do: {dyn_gettext("duration-#{duration}"), duration}
    )
  end

  defp occurence_options() do
    for(
      occurence <- @occurrences,
      do: {dyn_gettext("#{occurence} occurrences"), occurence}
    )
  end

  defp assign_changeset(
         %{
           assigns: %{
             booking_date: booking_date,
             current_user: %{nylas_detail: nylas_detail, time_zone: time_zone}
           }
         } = socket,
         params,
         action \\ nil
       ) do
    changeset =
      booking_date
      |> BookingEventDate.changeset(params)
      |> Map.put(:action, action)

    event = current(changeset)
    open_slots = Enum.count(event.slots, &(&1.status == :open))

    socket
    |> assign(
      changeset: changeset,
      open_slots: open_slots,
      external_calendar_events: get_external_events(nylas_detail, event, time_zone)
    )
  end

  defp assign_changeset_with_existing_slots(socket, params, action \\ :validate) do
    slots =
      params
      |> Map.get("slots")
      |> Map.values()
      |> Enum.sort(&(&1["slot_start"] < &2["slot_start"]))

    socket |> assign_changeset(Map.replace(params, "slots", slots), action)
  end

  defp assign_changeset_with_slots(
         %{
           assigns: %{
             booking_date: booking_date,
             booking_event: booking_event
           }
         } = socket,
         params,
         action
       ) do
    socket = socket |> assign_changeset(params, :validate)
    changeset = socket.assigns.changeset
    event_date = current(changeset)

    slots = event_date |> BookingEventDates.available_slots(booking_event)

    updated_slots =
      %{
        slots: slots,
        date: event_date.date,
        session_length: event_date.session_length,
        session_gap: event_date.session_gap
      }
      |> BookingEvents.filter_booking_slots(booking_event)

    open_slots = Enum.count(updated_slots, &(&1.status == :open))

    slots =
      updated_slots
      |> Enum.map(&(&1 |> Map.from_struct() |> Map.drop([:__meta__, :job, :client])))

    params = Map.put(params, "slots", slots)
    changeset = booking_date |> BookingEventDate.changeset(params) |> Map.put(:action, action)
    socket |> assign(changeset: changeset, open_slots: open_slots)
  end

  defp get_external_events(nylas_detail, event_date, time_zone) do
    if nylas_detail.external_calendar_rw_id && nylas_detail.oauth_token &&
         Map.get(event_date, :date) do
      start_date =
        DateTime.new!(event_date.date, ~T[00:00:00], time_zone)
        |> DateTime.to_unix()

      end_date =
        DateTime.new!(event_date.date, ~T[23:59:59], time_zone)
        |> DateTime.to_unix()

      {:ok, external_events} =
        NylasCalendar.get_events(
          nylas_detail.external_calendar_rw_id,
          nylas_detail.oauth_token,
          {start_date, end_date}
        )

      external_events
      |> Enum.reject(fn %{"description" => desc} -> desc == "\n[From Todoplace]\n" end)
      |> Enum.map(&to_datetime(&1, time_zone))
      |> Enum.reject(&is_nil(&1))
    end || []
  end

  defp hidden_time?(:hidden), do: true
  defp hidden_time?(_state), do: false

  defp slot_status(s), do: s |> current |> Map.get(:status)

  defp slot_already_booked?(s), do: s |> current |> Map.get(:is_already_booked)

  defp get_buffer_text(nil, _session_length, _slot_start, _end_time, _index, _length), do: nil
  defp get_buffer_text("", _session_length, _slot_start, _end_time, _index, _length), do: nil

  defp get_buffer_text(session_gap, session_length, slot_start, end_time, index, length) do
    buffer_text = "(+#{session_gap} min gap)"

    cond do
      length == 1 and slot_has_buffer?(slot_start, end_time, session_length, session_gap) ->
        buffer_text

      index != length - 1 ->
        buffer_text

      index == length - 1 and slot_has_buffer?(slot_start, end_time, session_length, session_gap) ->
        buffer_text

      true ->
        ""
    end
  end

  defp slot_has_buffer?(slot_start, end_time, session_length, session_gap) do
    slot_end_time = slot_start |> Time.add((session_length + session_gap) * 60)
    slot_end_time <= end_time
  end

  defp get_event_time(changeset) do
    [%{end_time: end_time} | _tail] = changeset |> get_field(:time_blocks)
    end_time
  end
end
