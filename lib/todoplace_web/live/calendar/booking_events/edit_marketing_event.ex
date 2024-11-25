defmodule TodoplaceWeb.Live.Calendar.EditMarketingEvent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.LiveModal, only: [close_x: 1, footer: 1]
  import TodoplaceWeb.Shared.ImageUploadInput, only: [image_upload_input: 1]
  import TodoplaceWeb.Shared.Quill, only: [quill_input: 1]
  import TodoplaceWeb.ClientBookingEventLive.Shared, only: [blurred_thumbnail: 1]
  alias Todoplace.{BookingEvent, BookingEvents}

  @impl true
  def update(%{event_id: event_id, current_user: user} = assigns, socket) do
    booking_event = BookingEvents.get_booking_event!(user.organization_id, event_id)

    socket
    |> assign(assigns)
    |> assign(:booking_event, booking_event)
    |> assign(show_on_public_profile?: booking_event.show_on_profile?)
    |> assign_changeset(%{})
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal">
      <.close_x />
      <h1 class="mt-2 mb-4 text-xl"><strong class="font-bold">Edit marketing details</strong></h1>
      <.form :let={f} for={@changeset} phx-change="validate" phx-submit="submit" phx-target={@myself}>
        <div class="flex flex-col mt-4">
          <div class="grid sm:grid-cols-2 gap-7 mt-2">
            <div class="flex flex-col">
              <label for={input_name(f, :thumbnail_url)} class="input-label font-bold">
                Thumbnail
              </label>
              <.image_upload_input
                current_user={@current_user}
                upload_folder="booking_event_image"
                name={input_name(f, :thumbnail_url)}
                url={input_value(f, :thumbnail_url)}
                class="aspect-[3/2] mt-2"
              >
                <:image_slot>
                  <.blurred_thumbnail
                    class="h-full w-full rounded-lg"
                    url={input_value(f, :thumbnail_url)}
                  />
                </:image_slot>
              </.image_upload_input>
              <.toggle_visibility
                title="Show event on my Public Profile?"
                event="toggle_visibility"
                myself={@myself}
                show_on_public_profile?={@show_on_public_profile?}
              />
            </div>
            <div class="flex flex-col">
              <%= labeled_input(f, :name,
                label: "Name",
                placeholder: "Fall Mini-sessions",
                wrapper_class: "sm:col-span-2",
                label_class: "font-bold"
              ) %>
              <label for={input_name(f, :description)} class="input-label mt-6 font-bold">
                Description
              </label>
              <.quill_input
                f={f}
                html_field={:description}
                enable_size={true}
                enable_image={true}
                current_user={@current_user}
                class="aspect-[3/2] mt-2"
                editor_class="h-[20rem]"
                placeholder="Use this area to describe your mini-session event or limited-edition session. Describe what is included in the package (eg, the location, length of time, digital images etc)."
              />
            </div>
          </div>
        </div>
        <.footer>
          <button
            class="btn-primary"
            title="Save"
            type="submit"
            disabled={!@changeset.valid?}
            phx-disable-with="Save"
          >
            Save
          </button>
          <button
            class="btn-secondary"
            title="Close"
            type="button"
            phx-click="modal"
            phx-value-action="close"
          >
            Close
          </button>
        </.footer>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_visibility", _, %{assigns: assigns} = socket) do
    socket
    |> assign(:show_on_public_profile?, !assigns.show_on_public_profile?)
    |> noreply()
  end

  @impl true
  def handle_event("validate", %{"booking_event" => params}, socket) do
    params = Map.put_new(params, "buffer_minutes", "")
    socket |> assign_changeset(params, :validate) |> noreply()
  end

  @impl true
  def handle_event(
        "submit",
        %{"booking_event" => params},
        %{assigns: %{show_on_public_profile?: show_on_public_profile?}} = socket
      ) do
    params = Map.put_new(params, "show_on_profile?", show_on_public_profile?)
    %{assigns: %{changeset: changeset}} = socket = assign_changeset(socket, params)

    case BookingEvents.upsert_booking_event(changeset) do
      {:ok, booking_event} ->
        successfull_save(socket, booking_event)

      _ ->
        socket |> noreply()
    end
  end

  @spec open(Phoenix.LiveView.Socket.t(), %{
          event_id: any,
          current_user: any
        }) :: Phoenix.LiveView.Socket.t()
  def open(socket, assigns) do
    socket
    |> open_modal(__MODULE__, assigns)
  end

  defp successfull_save(socket, booking_event) do
    send(
      self(),
      {:update, %{booking_event: booking_event |> BookingEvents.preload_booking_event()}}
    )

    socket
    |> close_modal()
    |> noreply()
  end

  defp assign_changeset(
         %{assigns: %{booking_event: booking_event}} = socket,
         params,
         action \\ nil
       ) do
    changeset =
      booking_event
      |> BookingEvent.update_customize(params)
      |> Map.put(:action, action)

    assign(socket,
      changeset: changeset
    )
  end

  defp toggle_visibility(%{show_on_public_profile?: show_on_public_profile?} = assigns) do
    class_1 = if show_on_public_profile?, do: ~s(bg-blue-planning-300), else: ~s(bg-white)

    class_2 =
      if show_on_public_profile?, do: ~s(right-1 bg-white), else: ~s(left-1 bg-blue-planning-300)

    assigns = assign(assigns, class_1: class_1, class_2: class_2)

    ~H"""
    <div class="flex mt-4 lg:mt-8">
      <div class="flex items-center">
        <div class="text-sm font-bold lg:text-normal text-black"><%= @title %></div>
        <label class="relative ml-4 cursor-pointer">
          <input type="checkbox" class="sr-only" phx-click={@event} phx-target={@myself} />
          <div class={"block border rounded-full h-6 w-10 border-blue-planning-300 #{@class_1}"}>
          </div>
          <div class={"absolute w-4 h-4 rounded-full dot top-1 transition #{@class_2}"}></div>
        </label>
      </div>
    </div>
    """
  end
end
