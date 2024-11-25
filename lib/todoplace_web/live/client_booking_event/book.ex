defmodule TodoplaceWeb.ClientBookingEventLive.Book do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "live_client"]

  alias Todoplace.{
    BookingEvents,
    BookingEvent,
    BookingEventDates
  }

  import TodoplaceWeb.PackageLive.Shared, only: [current: 1]

  import TodoplaceWeb.Live.Profile.Shared,
    only: [
      assign_organization_by_slug_on_profile_disabled: 2,
      photographer_logo: 1,
      profile_footer: 1
    ]

  import TodoplaceWeb.ClientBookingEventLive.Shared,
    only: [
      maybe_event_disable_or_archive: 1
    ]

  import TodoplaceWeb.Calendar.BookingEvents.Shared,
    only: [get_external_events: 1, external_event_overlap?: 4]

  import TodoplaceWeb.ClientBookingEventLive.DatePicker, only: [date_picker: 1]
  require Logger

  @impl true
  def mount(%{"organization_slug" => slug, "id" => event_id}, session, socket) do
    socket
    |> assign_defaults(session)
    |> assign_organization_by_slug_on_profile_disabled(slug)
    |> assign_booking_event(event_id)
    |> then(fn socket ->
      Todoplace.Shoots.subscribe_shoot_change(socket.assigns.organization.id)

      socket
      |> assign_changeset(%{
        "date" => socket.assigns.booking_event |> available_dates() |> Enum.at(0)
      })
    end)
    |> assign_available_times()
    |> maybe_event_disable_or_archive()
    |> assign_time_zone()
    |> get_external_events()
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @status == :active do %>
      <div class="center-container px-8 pt-6 mx-auto min-h-screen flex flex-col">
        <div class="flex">
          <.photographer_logo organization={@organization} />
        </div>
        <hr class="border-gray-100 my-8" />

        <div class="sm:mt-6 sm:mx-auto border border-gray-100 flex flex-col p-8 max-w-screen-lg">
          <h1 class="text-3xl">Booking with <%= @organization.name %></h1>
          <hr class="border-gray-100 my-8" />
          <h2 class="text-2xl">Your details</h2>

          <.form :let={f} for={@changeset} phx-change="validate" phx-submit="save">
            <div class="grid gap-5 sm:grid-cols-2 mt-4">
              <%= labeled_input(f, :name,
                label: "Your name",
                placeholder: "Type your first and last name…",
                phx_debounce: "500"
              ) %>
              <%= labeled_input(f, :email,
                type: :email_input,
                label: "Your email",
                placeholder: "Type email…",
                phx_debounce: "500"
              ) %>
              <div class="flex flex-col">
                <%= label_for(f, :phone, label: "Your phone number") %>
                <.live_component
                  module={LivePhone}
                  id="phone"
                  form={f}
                  field={:phone}
                  tabindex={0}
                  preferred={["US", "CA"]}
                />
              </div>
            </div>

            <hr class="border-gray-100 my-8 sm:my-12" />
            <h2 class="text-2xl mb-2">Pick your session time</h2>

            <div class="grid sm:grid-cols-2 gap-10">
              <.date_picker
                name={input_name(f, :date)}
                selected_date={input_value(f, :date)}
                available_dates={available_dates(@booking_event)}
              />
              <.time_picker
                name={input_name(f, :time)}
                selected_date={input_value(f, :date)}
                selected_time={input_value(f, :time)}
                available_slots={
                  available_slots(@booking_event, @booking_date, @time_zone, @external_events)
                }
              />
            </div>

            <div class="flex flex-col py-6 bg-white gap-5 mt-4 sm:mt-2 sm:flex-row-reverse">
              <button
                class="btn-primary w-full sm:w-36"
                title="next"
                type="submit"
                disabled={!@changeset.valid?}
                phx-disable-with="Next"
              >
                Next
              </button>

              <.live_link
                to={~p"/photographer/#{@organization.slug}/event/#{@booking_event.id}"}
                class="btn-secondary flex items-center justify-center w-full sm:w-48"
              >
                Cancel
              </.live_link>
            </div>
          </.form>
        </div>

        <hr class="border-gray-100 mt-8 sm:mt-20" />

        <.profile_footer color={@color} photographer={@photographer} organization={@organization} />
      </div>
    <% else %>
      <div class="center-container px-8 pt-6 mx-auto min-h-screen flex flex-col">
        <h1 class="text-1x text-center">No available times</h1>
      </div>
    <% end %>
    """
  end

  defp time_picker(assigns) do
    ~H"""
    <div {testid("time_picker")}>
      <%= if @selected_time do %>
        <input type="hidden" name={@name} value={@selected_time} />
      <% end %>
      <%= if @selected_date do %>
        <p><%= @selected_date |> Calendar.strftime("%A, %B %-d") %></p>
      <% end %>
      <div class="max-h-96 overflow-auto px-4">
        <%= if Enum.empty?(@available_slots) do %>
          <p class="mt-2">No available times</p>
        <% end %>
        <%= Enum.map(@available_slots, fn slot -> %>
          <label class={
            classes(
              "flex items-center justify-center border border-black py-3 my-4 cursor-pointer",
              %{
                "bg-black text-white" =>
                  Time.compare(slot.slot_start, @selected_time || Time.utc_now()) == :eq,
                "bg-white !text-grey !border-grey pointer-events-none opacity-40 hover:cursor-not-allowed" =>
                  disabled_slot?(slot.status)
              }
            )
          }>
            <%= slot.slot_start |> Calendar.strftime("%-I:%M%P") %>
            <input
              type="radio"
              name={@name}
              value={slot.slot_start}
              class="hidden"
              disabled={disabled_slot?(slot.status)}
            />
          </label>
        <% end ) %>
      </div>
    </div>
    """
  end

  defp assign_booking_event(%{assigns: %{organization: organization}} = socket, event_id) do
    socket
    |> assign(
      booking_event: BookingEvents.get_preloaded_booking_event!(organization.id, event_id)
    )
  end

  @impl true
  def handle_event("validate", %{"booking" => params, "_target" => ["booking", "date"]}, socket) do
    socket
    |> assign_changeset(params |> Map.put("time", nil), :validate)
    |> assign_available_times()
    |> noreply()
  end

  @impl true
  def handle_event("validate", %{"booking" => params}, socket) do
    socket |> assign_changeset(params, :validate) |> noreply()
  end

  @impl true
  def handle_event("save", %{"booking" => params}, socket) do
    %{
      assigns: %{
        changeset: changeset,
        booking_event: booking_event,
        time_zone: time_zone,
        external_events: external_events,
        booking_date: booking_date
      }
    } =
      socket
      |> assign_changeset(params, :validate)
      |> assign_available_times()

    booking = current(changeset)

    is_slot_not_booked_already? =
      booking_event
      |> available_slots(booking_date, time_zone, external_events)
      |> Enum.any?(&(Time.compare(&1.slot_start, booking.time) == :eq and &1.status == :open))

    slot_index = Enum.find_index(booking_date.slots, &(&1.slot_start == booking.time))

    with true <- is_slot_not_booked_already?,
         {:available, true} <- {:available, time_available?(booking, booking_date.id)},
         {:ok, %{proposal: proposal, shoot: shoot}} <-
           BookingEvents.save_booking(booking_event, booking_date, booking, %{
             slot_index: slot_index,
             slot_status: :booked
           }) do
      Todoplace.Shoots.broadcast_shoot_change(shoot)

      socket
      |> push_redirect(to: Todoplace.BookingProposal.path(proposal.id))
      |> noreply()
    else
      {:available, false} ->
        socket
        |> put_flash(:error, "This time is not available anymore")
        |> noreply()

      e ->
        Logger.warning("[save_booking] error: #{inspect(e)}")

        socket
        |> put_flash(:error, "Couldn't book this event.")
        |> noreply()
    end
  end

  def handle_info({:shoot_updated, _shoot}, socket) do
    socket
    |> assign_available_times()
    |> noreply()
  end

  defp assign_time_zone(%{assigns: %{current_user: current_user} = assigns} = socket) do
    time_zone =
      if current_user do
        current_user
      else
        Map.get(assigns, :organization) |> Map.get(:user)
      end
      |> Map.get(:time_zone)

    assign(socket, time_zone: time_zone)
  end

  defp assign_changeset(socket, params, action \\ nil) do
    changeset = params |> BookingEvents.Booking.changeset() |> Map.put(:action, action)
    assign(socket, changeset: changeset)
  end

  defp available_dates(%BookingEvent{} = booking_event) do
    booking_event
    |> Map.get(:dates)
    |> Enum.map(& &1.date)
    |> Enum.sort_by(& &1, Date)
    |> Enum.filter(fn date ->
      Date.compare(date, Date.utc_today()) != :lt
    end)
  end

  defp time_available?(booking, booking_date_id) do
    available_slots =
      BookingEventDates.get_booking_event_date(booking_date_id) |> Map.get(:slots, [])

    Enum.any?(
      available_slots,
      &(Time.compare(&1.slot_start, booking.time) == :eq and &1.status == :open)
    )
  end

  defp assign_available_times(
         %{assigns: %{booking_event: booking_event, changeset: changeset}} = socket
       ) do
    booking = current(changeset)

    booking_date =
      if booking.date do
        [booking_date | _] =
          BookingEventDates.get_booking_events_dates_with_same_date(
            [booking_event.id],
            booking.date
          )

        booking_date
      else
        []
      end

    socket |> assign(booking_date: booking_date)
  end

  defp disabled_slot?(:open), do: false
  defp disabled_slot?(_status), do: true

  defp available_slots(booking_event, booking_event_date, time_zone, external_events) do
    if is_list(booking_event_date) do
      []
    else
      date = booking_event_date.date
      slots = BookingEvents.filter_booking_slots(booking_event_date, booking_event)

      if external_events do
        slots
        |> Enum.map(fn slot ->
          check_external_slot_booked(date, slot, external_events, time_zone)
        end)
      else
        slots
      end
    end
  end

  defp check_external_slot_booked(date, slot, external_events, time_zone) do
    external_book? =
      external_events
      |> Enum.any?(fn event ->
        external_event_overlap?(date, slot, event, time_zone)
      end)

    if external_book? do
      %{slot | status: :reserved}
    else
      slot
    end
  end
end
