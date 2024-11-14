defmodule TodoplaceWeb.Calendar.BookingEvents.Shared do
  @moduledoc "shared functions for booking events"

  use TodoplaceWeb, :html

  use Phoenix.Component
  require Logger

  import Phoenix.LiveView
  import TodoplaceWeb.LiveHelpers
  import TodoplaceWeb.Gettext, only: [ngettext: 3]
  import TodoplaceWeb.Live.Shared, only: [make_popup: 2]
  import TodoplaceWeb.Helpers, only: [job_url: 1]
  import TodoplaceWeb.GalleryLive.Shared, only: [add_message_and_notify: 3]
  import Todoplace.Notifiers, only: [email_signature: 1]
  import TodoplaceWeb.PackageLive.Shared, only: [current: 1]

  alias TodoplaceWeb.{
    SearchComponent,
    ConfirmationComponent,
    ClientMessageComponent,
    Shared.SelectionPopupModal,
    PackageLive.WizardComponent,
    Live.Calendar.BookingEvents.Index,
    LeadLive.Show
  }

  alias Todoplace.{
    Repo,
    Utils,
    Client,
    Clients,
    Package,
    BookingEvent,
    BookingEvents,
    BookingProposal,
    BookingEventDate,
    BookingEventDates,
    BookingEventTemplates,
    BookingEventDate.SlotBlock,
    NylasCalendar
  }

  alias Ecto.Multi
  alias TodoplaceWeb.Router.Helpers, as: Routes

  def handle_event(
        "duplicate-event",
        params,
        %{assigns: %{current_user: %{organization_id: org_id}}} = socket
      ) do
    BookingEvents.duplicate_booking_event(fetch_booking_event_id(params, socket), org_id)
    |> case do
      {:ok, %{duplicate_booking_event: new_event}} ->
        socket
        |> redirect(to: "/booking-events/#{new_event.id}")

      {:error, :duplicate_booking_event, _, _} ->
        socket
        |> put_flash(:error, "Unable to duplicate event")

      _ ->
        socket
        |> put_flash(:error, "Unexpected error")
    end
    |> noreply()
  end

  def handle_event("new-event", %{}, socket),
    do:
      socket
      |> SelectionPopupModal.open(%{
        heading: "Create a Booking Event",
        title_one: "Single Event",
        subtitle_one: "Best for a single weekend or a few days you’d like to fill.",
        icon_one: "calendar-add",
        btn_one_event: "create-single-event",
        title_two: "Repeating Event",
        subtitle_two:
          "Best for an event you’d like to run every week, weekend, every month, etc.",
        icon_two: "calendar-repeat",
        btn_two_event: "create-repeating-event"
      })
      |> noreply()

  def handle_event("confirm-archive-event", params, socket) do
    socket
    |> ConfirmationComponent.open(%{
      title: "Are you sure?",
      subtitle: """
      Are you sure you want to archive this event?
      """,
      confirm_event: "archive_event_#{fetch_booking_event_id(params, socket)}",
      confirm_label: "Yes, archive",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  def handle_event("confirm-disable-event", params, socket) do
    socket
    |> ConfirmationComponent.open(%{
      title: "Disable this event?",
      subtitle: """
      Disabling this event will hide all availability for this event and prevent any further booking. This is also the first step to take if you need to cancel an event for any reason.

      Some things to keep in mind:
        • If you are no longer able to shoot at the date
          and time provided, let your clients know. We
          suggest offering them a new link to book with
          once you reschedule!
        • You may need to refund any payments made
          to prevent confusion with your clients.
        • Archive each job individually in the Jobs page
          if you intend to cancel it.
        • Reschedule if possible to keep business
          coming in!
      """,
      confirm_event: "disable_event_#{fetch_booking_event_id(params, socket)}",
      confirm_label: "Disable event",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  def handle_event(
        "enable-event",
        params,
        %{assigns: %{current_user: %{organization: organization}}} = socket
      ) do
    params
    |> fetch_booking_event_id(socket)
    |> BookingEvents.enable_booking_event(organization.id)
    |> case do
      {:ok, _event} ->
        socket
        |> assign_events()
        |> put_flash(:success, "Event enabled successfully")

      {:error, _} ->
        socket
        |> put_flash(:success, "Error enabling event")
    end
    |> noreply()
  end

  def handle_event(
        "unarchive-event",
        params,
        %{assigns: %{current_user: %{organization: organization}}} = socket
      ) do
    params
    |> fetch_booking_event_id(socket)
    |> BookingEvents.enable_booking_event(organization.id)
    |> case do
      {:ok, _event} ->
        socket
        |> assign_events()
        |> put_flash(:success, "Event unarchived successfully")

      {:error, _} ->
        socket
        |> put_flash(:success, "Error unarchiving event")
    end
    |> noreply()
  end

  def handle_event("confirm-delete-date", _params, socket) do
    socket
    |> ConfirmationComponent.open(%{
      title: "Are you sure?",
      subtitle: "Are you sure you want to delete this date?",
      confirm_event: "delete_date",
      confirm_label: "Yes, delete",
      close_label: "Cancel",
      icon: "warning-orange"
    })
    |> noreply()
  end

  def handle_event(
        "confirm-cancel-session",
        %{
          "booking_event_date_id" => booking_event_date_id,
          "slot_index" => slot_index
        },
        socket
      ) do
    socket
    |> ConfirmationComponent.open(%{
      title: "Cancel session?",
      subtitle:
        "Are you sure you want to cancel this session? You'll have to refund them through Stripe or whatever payment method you use previously",
      confirm_event: "cancel_session",
      confirm_label: "Yes, cancel",
      close_label: "Cancel",
      icon: "warning-orange",
      payload: %{
        booking_event_date_id: String.to_integer(booking_event_date_id),
        slot_index: String.to_integer(slot_index),
        slot_update_args: %{status: :open, client_id: nil, job_id: nil}
      }
    })
    |> noreply()
  end

  def handle_event(
        "confirm-reschedule",
        %{
          "booking_event_date_id" => booking_event_date_id,
          "slot_client_id" => slot_client_id,
          "slot_index" => slot_index
        },
        %{assigns: %{current_user: current_user, booking_event: booking_event}} = socket
      ) do
    [booking_event_date_id, slot_client_id, slot_index] =
      to_integer([booking_event_date_id, slot_client_id, slot_index])

    dates_with_slots =
      booking_event.dates
      |> Enum.filter(fn %{date: date} -> Date.compare(date, Date.utc_today()) in [:gt, :eq] end)
      |> Enum.map(fn date ->
        date_slots =
          date
          |> BookingEvents.filter_booking_slots(booking_event)
          |> Enum.with_index(fn slot, slot_index ->
            show? = if slot.status == :open, do: true, else: false
            {"#{parse_time(slot.slot_start)} - #{parse_time(slot.slot_end)}", slot_index, show?}
          end)
          |> Enum.reject(fn
            {_, _, true} -> false
            _ -> true
          end)

        %{id: date.id, date: date_formatter(date.date, :day), slots: date_slots}
      end)
      |> Enum.map(fn
        %{id: ^booking_event_date_id} = date_slots ->
          updated_slots =
            date_slots
            |> Map.get(:slots, [])
            |> Enum.reject(fn {_, index, _} -> index == slot_index end)

          date_slots |> Map.put(:slots, updated_slots)

        any ->
          any
      end)

    socket
    |> make_popup(
      icon: nil,
      dropdown?: true,
      close_label: "Cancel",
      class: "dialog",
      title: "Reschedule session",
      confirm_label: "Reschedule",
      confirm_class: "btn-primary",
      dropdown_label: "Pick a new time",
      empty_dropdown_description: "Sorry, no slots available for rescheduling now",
      confirm_event: "reschedule_session",
      payload: %{
        booking_event_date_id: booking_event_date_id,
        slot_index: slot_index,
        slot_client_id: slot_client_id,
        client_name: slot_client_name(current_user, slot_client_id),
        client_icon: "client-icon",
        dates_with_slots: dates_with_slots
      }
    )
  end

  def handle_event(
        "confirm-mark-hide",
        %{"booking_event_date_id" => booking_event_date_id, "slot_index" => slot_index},
        socket
      ) do
    socket
    |> ConfirmationComponent.open(%{
      title: "Mark block hidden?",
      subtitle:
        "This is useful if you'd like to give yourself a break or make yourself look booked at this time and open it up later",
      confirm_event: "change_slot_status",
      confirm_class: "btn-primary",
      confirm_label: "Hide block",
      close_label: "Cancel",
      icon: nil,
      payload: %{
        booking_event_date_id: to_integer(booking_event_date_id),
        slot_index: to_integer(slot_index),
        slot_update_args: %{status: :hidden}
      }
    })
    |> noreply()
  end

  def handle_event(
        "confirm-mark-open",
        %{"booking_event_date_id" => booking_event_date_id, "slot_index" => slot_index},
        socket
      ) do
    socket
    |> ConfirmationComponent.open(%{
      title: "Mark block open?",
      subtitle: "Are you sure you want to allow this block to be bookable by clients?",
      confirm_event: "change_slot_status",
      confirm_class: "btn-primary",
      confirm_label: "Show block",
      close_label: "Cancel",
      icon: nil,
      payload: %{
        booking_event_date_id: String.to_integer(booking_event_date_id),
        slot_index: String.to_integer(slot_index),
        slot_update_args: %{status: :open, client_id: nil}
      }
    })
    |> noreply()
  end

  def handle_event("open-client", params, socket) do
    params
    |> Map.get("slot_client_id", nil)
    |> case do
      nil ->
        socket
        |> put_flash(:error, "Unable to open the client")

      client_id ->
        socket
        |> redirect(to: "/clients/#{to_integer(client_id)}")
    end
    |> noreply()
  end

  def handle_event(
        "open-job",
        params,
        socket
      ) do
    params
    |> Map.get("slot_job_id", nil)
    |> case do
      nil ->
        socket
        |> put_flash(:error, "There is no job assigned. Please set a job first.")

      job_id ->
        socket
        |> redirect(to: "/jobs/#{to_integer(job_id)}")
    end
    |> noreply()
  end

  def handle_event(
        "open-lead",
        params,
        socket
      ) do
    params
    |> Map.get("slot_job_id", nil)
    |> case do
      nil ->
        socket
        |> put_flash(:error, "There is no lead assigned. Please set a lead first.")

      lead_id ->
        socket
        |> redirect(to: "/leads/#{to_integer(lead_id)}")
    end
    |> noreply()
  end

  def handle_event(
        "confirm-reserve",
        %{"booking_event_date_id" => booking_event_date_id, "slot_index" => slot_index},
        %{assigns: %{current_user: current_user, booking_event: booking_event}} = socket
      ) do
    [booking_event_date_id, slot_index] = to_integer([booking_event_date_id, slot_index])

    booking_event_date = get_booking_date(booking_event, booking_event_date_id)
    slot = Enum.at(booking_event_date.slots, slot_index)
    clients = Clients.find_all_by(user: current_user)

    socket
    |> assign(:clients, clients)
    |> SearchComponent.open(%{
      close_label: "Cancel",
      change_event: :change_client,
      submit_event: :reserve_session,
      save_label: "Reserve",
      title: "Reserve session",
      icon: "clock",
      placeholder: "Search clients by email or first/last name…",
      empty_result_description: "No client found with that information",
      component_used_for: :booking_events_search,
      payload: %{
        clients: clients,
        booking_event: booking_event,
        booking_event_date: booking_event_date,
        slot_index: slot_index,
        slot: slot
      }
    })
    |> noreply()
  end

  def handle_event(
        "send-email",
        %{"id" => date_id},
        %{
          assigns: %{
            booking_event: booking_event,
            current_user: %{organization: organization} = current_user
          }
        } = socket
      ) do
    phone = if current_user.onboarding.phone, do: " at #{current_user.onboarding.phone}"

    data = %{
      "photographer_cell" => phone,
      "booking_event_name" => booking_event.name,
      "email_signature" => email_signature(organization |> Repo.preload(:user))
    }

    socket
    |> ClientMessageComponent.open(%{
      current_user: current_user,
      modal_title: "Draft and send an ad hoc email to all booked clients",
      presets: [],
      body_html: short_codes_values(:date, data),
      subject:
        """
        Important note about #{booking_event.name} from #{organization.name}!
        """
        |> Utils.normalize_body_template(),
      send_button: "Send",
      booking_event?: true,
      recipients: get_recipients(socket, to_integer(date_id))
    })
    |> noreply()
  end

  def handle_event(
        "send-email",
        %{},
        %{
          assigns: %{
            booking_event: booking_event,
            current_user: %{organization: organization} = current_user
          }
        } = socket
      ) do
    data = %{
      "view_proposal_button" => """
          <a style="border:1px solid #1F1C1E;display:inline-block;background:white;color:#1F1C1E;font-family:Montserrat, sans-serif;font-size:18px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 15px;mso-padding-alt:0px;border-radius:0px;"
      target="_blank" href="#{booking_event.url}">
      View Booking Proposal
      </a>
      """,
      "photography_company_s_name" => organization.name,
      "email_signature" => email_signature(organization |> Repo.preload(:user))
    }

    socket
    |> ClientMessageComponent.open(%{
      current_user: current_user,
      modal_title: "Draft and send a marketing email to inform clients about this booking event",
      presets: [],
      body_html: short_codes_values(:marketing, data),
      subject: "You don’t want to miss the #{booking_event.name} from #{organization.name}!",
      send_button: "Send",
      booking_event?: true,
      recipients: get_recipients(socket)
    })
    |> noreply()
  end

  def handle_info(
        {:confirm_event, event},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      )
      when event in ["create-repeating-event", "create-single-event"] do
    case BookingEvents.create_booking_event(%{
           organization_id: organization_id,
           is_repeating: event == "create-repeating-event",
           name: "New event"
         }) do
      {:ok, booking_event} ->
        socket
        |> redirect(to: "/booking-events/#{booking_event.id}")

      {:error, _} ->
        socket
        |> put_flash(:error, "Unable to create booking event")
    end
    |> noreply()
  end

  def handle_info(
        {:update_templates, %{templates: templates}},
        %{assigns: %{modal_pid: modal_pid}} = socket
      ) do
    send_update(modal_pid, WizardComponent, id: WizardComponent, templates: templates)

    socket
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "confirm_duplicate_event",
         %{booking_event_id: event_id, organization_id: org_id}},
        socket
      ) do
    duplicate_booking_event =
      BookingEvents.get_booking_event!(
        org_id,
        event_id
      )
      |> Repo.preload([:dates])
      |> Map.put(:status, :active)
      |> Map.from_struct()

    duplicate_event_dates =
      duplicate_booking_event
      |> Map.get(:dates, nil)
      |> Enum.map(fn t ->
        t
        |> Map.replace(:date, nil)
        |> Map.replace(:slots, edit_slots_status(t))
      end)

    multi =
      Multi.new()
      |> Multi.insert(
        :duplicate_booking_event,
        BookingEvent.duplicate_changeset(duplicate_booking_event)
      )

    duplicate_event_dates
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {event_date, i}, multi ->
      multi
      |> Multi.insert(
        "duplicate_booking_event_date_#{i}",
        fn %{duplicate_booking_event: event} ->
          BookingEventDate.changeset(%{
            booking_event_id: event.id,
            location: event_date.location,
            address: event_date.address,
            session_length: event_date.session_length,
            session_gap: event_date.session_gap,
            time_blocks: BookingEvents.to_map(event_date.time_blocks),
            slots: BookingEvents.to_map(event_date.slots)
          })
        end
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{duplicate_booking_event: new_event}} ->
        socket
        |> redirect(to: "/booking-events/#{new_event.id}")

      {:error, :duplicate_booking_event, _, _} ->
        socket
        |> put_flash(:error, "Unable to duplicate event")

      _ ->
        socket
        |> put_flash(:error, "Unexpected error")
    end
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "change_slot_status",
         %{
           booking_event_date_id: booking_event_date_id,
           slot_index: slot_index,
           slot_update_args: slot_update_args
         }},
        socket
      ) do
    case BookingEventDates.update_slot_status(booking_event_date_id, slot_index, slot_update_args) do
      {:ok, _booking_event_date} ->
        socket
        |> assign_events()
        |> put_flash(:success, "Slot changed successfully")

      {:error, _} ->
        socket
        |> put_flash(:error, "Error changing slot status")
    end
    |> close_modal()
    |> noreply()
  end

  def handle_info({:confirm_event, "delete_date"}, socket) do
    socket |> close_modal() |> noreply()
  end

  def handle_info(
        {:confirm_event, "reschedule_session",
         %{
           booking_event_date_id: booking_event_date_id,
           item_id: item_id,
           slot_client_id: slot_client_id,
           slot_index: slot_index,
           old_booking_event_date_id: old_booking_event_date_id
         }},
        %{assigns: %{current_user: user, booking_event: booking_event}} = socket
      ) do
    booking_event_date = get_booking_date(booking_event, to_integer(booking_event_date_id))

    old_booking_event_date =
      get_booking_date(booking_event, to_integer(old_booking_event_date_id))

    slot =
      old_booking_event_date.slots
      |> Enum.at(slot_index)

    new_slot =
      booking_event_date
      |> BookingEventDates.available_slots(booking_event)
      |> Enum.at(to_integer(item_id))

    {_, new_slot_index} =
      booking_event_date.slots
      |> Enum.with_index(fn slot, slot_index -> {slot, slot_index} end)
      |> Enum.filter(fn {slot, _slot_index} ->
        slot.slot_start == new_slot.slot_start && slot.slot_end == new_slot.slot_end
      end)
      |> hd

    with %Client{name: name} <- slot_client(user, slot_client_id),
         {:ok, latest_booking_event_date} <-
           BookingEvents.reschedule_booking(
             old_booking_event_date,
             booking_event_date,
             %{old_slot_index: slot_index, slot_index: new_slot_index, slot_status: slot.status}
           ),
         shoot <- slot.job |> Repo.preload(:shoots) |> Map.get(:shoots) |> hd(),
         _shoot_updated <-
           Todoplace.Shoot.update_shoot_time_address!(
             shoot,
             DateTime.new!(latest_booking_event_date.date, new_slot.slot_start, user.time_zone)
             |> DateTime.shift_zone!("Etc/UTC"),
             latest_booking_event_date.address
           ) do
      slot = Enum.at(latest_booking_event_date.slots, new_slot_index)
      job = slot.job
      proposal = hd(job.booking_proposals)
      Todoplace.Shoots.broadcast_shoot_change(shoot)
      class = "underline text-blue-planning-300"

      socket
      |> assign_events()
      |> make_popup(
        icon: nil,
        title: "Reschedule Session",
        subtitle: """
          Great! Session has been rescheduled and a <a class="#{class}" href="#{job_url(job.id)}" target="_blank">job</a> + <a class="#{class}" href="#{BookingProposal.url(proposal.id)}" target="_blank">client portal</a> has been created for you to share
        """,
        copy_btn_label: "Copy link, I’ll send separately",
        copy_btn_event: "copy-link",
        copy_btn_value: BookingProposal.url(proposal.id),
        confirm_event: "finish-proposal",
        confirm_class: "btn-primary",
        confirm_label: "Send client link via email",
        show_search: false,
        close_label: "Close",
        payload: %{
          client_name: name,
          client_icon: "client-icon",
          job: Todoplace.Jobs.get_job_by_id(job.id),
          proposal: proposal,
          slot_index: new_slot_index,
          booking_event_date: latest_booking_event_date,
          type: "rescheduled"
        }
      )
    else
      {:error, _} ->
        socket
        |> put_flash(:error, "Booking cannot be rescheduled, please try again")
        |> close_modal()
        |> noreply()

      e ->
        Logger.warning("[save_booking] error: #{inspect(e)}")

        socket
        |> put_flash(:error, "Couldn't reschedule this booking")
        |> close_modal()
        |> noreply()
    end
  end

  def handle_info(
        {:confirm_event, "cancel_session",
         %{
           booking_event_date_id: booking_event_date_id,
           slot_index: slot_index
         }},
        %{assigns: %{booking_event: booking_event}} = socket
      ) do
    booking_event_date = get_booking_date(booking_event, to_integer(booking_event_date_id))
    slot = Enum.at(booking_event_date.slots, slot_index)

    case BookingEvents.make_the_booking_expired(%{
           "id" => slot.job_id,
           "booking_date_id" => booking_event_date_id,
           "slot_index" => slot_index
         }) do
      {:ok, _} ->
        socket
        |> assign_events()
        |> put_flash(:success, "Session cancelled successfully!")

      {:error, _} ->
        socket
        |> put_flash(:error, "Error changing slot status")
    end
    |> close_modal()
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "disable_event_" <> id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case BookingEvents.disable_booking_event(id, current_user.organization_id) do
      {:ok, _event} ->
        socket
        |> assign_events()
        |> put_flash(:success, "Event disabled successfully")

      {:error, _} ->
        socket
        |> put_flash(:success, "Error disabling event")
    end
    |> close_modal()
    |> noreply()
  end

  def handle_info(
        {:confirm_event, "archive_event_" <> id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case BookingEvents.archive_booking_event(id, current_user.organization_id) do
      {:ok, _event} ->
        socket
        |> assign_events()
        |> put_flash(:success, "Event archived successfully")

      {:error, _} ->
        socket
        |> put_flash(:success, "Error archiving event")
    end
    |> close_modal()
    |> noreply()
  end

  def handle_info(
        {:search_event, :change_client, search},
        %{assigns: %{modal_pid: modal_pid, clients: clients}} = socket
      ) do
    send_update(modal_pid, SearchComponent,
      id: SearchComponent,
      results:
        Clients.search(search, clients) |> Enum.map(&%{id: &1.id, name: &1.name, email: &1.email}),
      search: search,
      selection: nil
    )

    socket
    |> noreply
  end

  def handle_info(
        {:search_event, :reserve_session, client,
         %{
           slot_index: slot_index,
           slot: slot,
           booking_event_date: booking_event_date,
           booking_event: booking_event
         }},
        %{assigns: %{current_user: _current_user}} = socket
      ) do
    {:ok, %{proposal: proposal, shoot: shoot, job: job}} =
      BookingEvents.save_booking(
        booking_event,
        booking_event_date,
        %{
          name: client.name,
          email: client.email,
          phone: nil,
          date: booking_event_date.date,
          time: slot.slot_start
        },
        %{slot_index: slot_index, slot_status: :reserved}
      )

    Todoplace.Shoots.broadcast_shoot_change(shoot)
    class = "underline text-blue-planning-300"

    socket
    |> assign_events()
    |> make_popup(
      icon: nil,
      title: "Reserve Session",
      subtitle: """
        Great! Session has been reserved and a <a class="#{class}" href={~p"/leads/#{job.id}"} target="_blank">job</a> + <a class="#{class}" href="#{BookingProposal.url(proposal.id)}" target="_blank">client portal</a> has been created for you to share
      """,
      copy_btn_label: "Copy link, I’ll send separately",
      copy_btn_event: "copy-link",
      copy_btn_value: BookingProposal.url(proposal.id),
      confirm_event: "finish-proposal",
      confirm_class: "btn-primary",
      confirm_label: "Send client link via email",
      show_search: false,
      close_label: "Cancel",
      payload: %{
        job: Todoplace.Jobs.get_job_by_id(job.id),
        proposal: proposal,
        client_name: client.name,
        client_icon: "client-icon",
        slot_index: slot_index,
        booking_event_date: get_booking_date(booking_event, booking_event_date.id),
        booking_event_date_id: booking_event_date.id
      }
    )
  end

  def handle_info(
        {:confirm_event, "finish-proposal",
         %{job: job, booking_event_date: booking_event_date, slot_index: slot_index} = payload},
        %{
          assigns: %{
            booking_event: booking_event,
            current_user: %{organization: organization} = current_user
          }
        } = socket
      ) do
    slot_scheduled_type = Map.get(payload, :type, nil)
    is_rescheduled? = if slot_scheduled_type == "rescheduled", do: true, else: false
    url = get_proposal_url(job)

    slot = Enum.at(booking_event_date.slots, slot_index)

    session_location =
      if booking_event_date.location in [nil, ""],
        do: booking_event_date.address,
        else: booking_event_date.location

    signature = email_signature(organization |> Repo.preload(:user))

    data = %{
      "view_proposal_button" => """
      <a style="border:1px solid #1F1C1E;display:inline-block;background:white;color:#1F1C1E;font-family:Montserrat, sans-serif;font-size:18px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 15px;mso-padding-alt:0px;border-radius:0px;"
      target="_blank" href="#{url}">
      View Booking Proposal
      </a>
      """,
      "client_first_name" => client_first_name(job),
      "booking_event_name" => booking_event.name,
      "photography_company_s_name" => organization.name,
      "session_date" => date_formatter(booking_event_date.date, :day),
      "session_time" => slot.slot_start |> Calendar.strftime("%I:%M %P"),
      "session_location" => session_location,
      "email_signature" => signature,
      "photographer_signature" => signature
    }

    socket
    |> assign(:job, job)
    |> ClientMessageComponent.open(%{
      composed_event: :proposal_message_composed,
      current_user: current_user,
      modal_title:
        "Draft and send a proposal email when a block is #{if is_rescheduled?, do: "rescheduled", else: "reserved"} for a client",
      enable_size: true,
      enable_image: true,
      presets: [],
      booking_event?: true,
      body_html: short_codes_values(slot.status, data),
      subject: get_subject_for_email(slot.status, organization.name),
      client: Todoplace.Job.client(job)
    })
    |> noreply()
  end

  def handle_info({:message_composed, message_changeset, recipients}, socket) do
    add_message_and_notify(socket, message_changeset, recipients)
  end

  defdelegate handle_info(message, socket), to: Show

  def overlap_time?(blocks), do: BookingEvents.overlap_time?(blocks)

  @doc """
  Edits the status of booking event date slots.

  This function takes a list of booking event date slots and edits their status. It iterates through each slot
  in the list and sets the status to either `:hidden` or `:open` based on the existing status. If the current
  status is `:hidden`, it remains unchanged; otherwise, it is updated to `:open`. This function is typically
  used to toggle the visibility of slots.

  ## Parameters

  - `slots` ([SlotBlock.t()]): A list of booking event date slots to edit.

  ## Returns

  A list of updated booking event date slots with modified status.

  ## Example

  ```elixir
  # Edit the status of booking event date slots
  iex> slots = [SlotBlock.t(), SlotBlock.t()]
  iex> edit_slots_status(%{slots: slots})
  [SlotBlock.t(), SlotBlock.t()]

  ## Notes

  This function is useful for modifying the status of booking event date slots, typically used to control their visibility
  """
  @spec edit_slots_status(map()) :: [SlotBlock.t()]
  def edit_slots_status(%{slots: slots}) do
    Enum.map(slots, fn s ->
      if s.status == :hidden, do: %{s | status: :hidden}, else: %{s | status: :open}
    end)
  end

  @spec update_slots_for_edit(map(), map()) :: [SlotBlock.t()]
  def update_slots_for_edit(%{slots: slots} = booking_date, booking_event) do
    slots =
      Enum.map(slots, fn s ->
        if s.status == :hidden, do: %{s | is_hide: true}, else: s
      end)

    booking_date |> Map.put(:slots, slots) |> BookingEvents.filter_booking_slots(booking_event)
  end

  def update_repeat_settings_for_edit(booking_date) do
    if booking_date.occurrences > 0,
      do: Map.replace(booking_date, :repetition, true),
      else: booking_date
  end

  def assign_events(
        %{
          assigns:
            %{booking_event: %{id: event_id}, current_user: %{organization: organization}} =
              assigns
        } = socket
      ) do
    %{package_template: package_template} =
      booking_event =
      organization.id
      |> BookingEvents.get_booking_event!(event_id)
      |> BookingEvents.preload_booking_event()
      |> put_url_booking_event(organization, socket)

    calendar_date_event =
      case booking_event do
        %{dates: []} ->
          nil

        %{dates: [date | _]} ->
          if Map.has_key?(assigns, :calendar_date_event) and
               Map.get(assigns, :calendar_date_event),
             do: Enum.find(booking_event.dates, &(&1.date == assigns.calendar_date_event.date)),
             else: date
      end

    socket
    |> assign(:booking_event, booking_event)
    |> assign(:package, package_template)
    |> assign(:payments_description, payments_description(booking_event))
    |> assign(:calendar_date_event, calendar_date_event)
  end

  def assign_events(%{assigns: %{booking_events: _booking_events}} = socket),
    do: Index.assign_booking_events(socket)

  def convert_date_string_to_date(nil), do: nil
  def convert_date_string_to_date(date), do: Date.from_iso8601!(date)

  def get_date(%{"date" => date}), do: date
  def get_date(%{date: date}), do: date

  def count_booked_slots(slot),
    do: Enum.count(slot, fn s -> s.status in [:booked, :reserved] end)

  def count_available_slots(slot), do: Enum.count(slot, fn s -> s.status == :open end)
  def count_hidden_slots(slot), do: Enum.count(slot, fn s -> s.status == :hidden end)

  # tells us if the created/duplicated booking event is complete or not
  # if we dont have dates or a package_template_id, then its incomplete
  # similarly its complete if both dates and package_template_id exist
  def incomplete_status?(%{package_template_id: nil}), do: true
  def incomplete_status?(%{dates: []}), do: true

  def incomplete_status?(%{dates: [%{"booking_event_id" => nil, "date" => nil, "id" => nil}]}),
    do: true

  def incomplete_status?(_), do: false

  # will be true if the status matches in the array <status_list>
  def disabled?(booking_event, status_list), do: booking_event.status in status_list

  def put_url_booking_event(booking_event, organization, socket),
    do:
      booking_event
      |> Map.put(
        :url,
        url(~p"/photographer/#{organization.slug}/event/#{booking_event.id}")
      )

  def get_booking_date(booking_event, date_id),
    do:
      booking_event.dates
      |> Enum.filter(fn date -> date.id == date_id end)
      |> hd()

  def get_booking_event_clients(booking_event, nil),
    do:
      booking_event.dates
      |> Enum.map(fn date ->
        get_clients(date)
      end)
      |> List.flatten()

  def get_booking_event_clients(booking_event, date_id),
    do:
      booking_event.dates
      |> Enum.filter(fn date -> date.id == date_id end)
      |> hd()
      |> get_clients()

  def slot_client(user, slot_client_id) do
    Clients.get_client(user, id: slot_client_id)
  end

  def slot_client_name(user, slot_client_id) do
    case slot_client(user, slot_client_id) do
      nil ->
        "Not found"

      client ->
        client
        |> Map.get(:name)
        |> Utils.capitalize_all_words()
    end
  end

  defp get_recipients(
         %{assigns: %{booking_event: booking_event, current_user: %{email: email}}},
         date_id \\ nil
       ) do
    clients = get_booking_event_clients(booking_event, date_id)

    cond do
      Enum.any?(clients) && length(clients) > 1 ->
        %{"to" => email, "bcc" => clients}

      Enum.any?(clients) ->
        %{"to" => email, "bcc" => clients}

      true ->
        %{"to" => email}
    end
  end

  defp get_clients(date) do
    date
    |> Map.get(:slots)
    |> Enum.filter(fn slot -> Map.get(slot, :client) end)
    |> Enum.reduce([], fn slot, acc -> [slot.client.email | acc] end)
  end

  # to cater different handle_event and info calls
  # if we get booking-event-id in params (1st argument) it returns the id
  # otherwise get the id from socket
  defp fetch_booking_event_id(%{"event-id" => id}, _assigns), do: id

  defp fetch_booking_event_id(%{}, %{assigns: %{booking_event: booking_event}}),
    do: booking_event.id

  defp payments_description(%{package_template: nil}), do: nil

  defp payments_description(%{
         package_template: %{package_payment_schedules: package_payment_schedules} = package
       }) do
    currency_symbol = Money.Currency.symbol!(package.currency)
    total_price = Package.price(package)
    {first_payment, remaining_payments} = package_payment_schedules |> List.pop_at(0)

    payment_count = Enum.count(remaining_payments)

    count_text =
      if payment_count > 0,
        do: ngettext(", 1 other payment", ", %{count} other payments", payment_count),
        else: nil

    if first_payment do
      interval_text =
        if first_payment.interval do
          "#{first_payment.due_interval}"
        else
          "#{first_payment.count_interval} #{first_payment.time_interval} #{first_payment.shoot_interval}"
        end

      if first_payment.percentage do
        amount = (total_price.amount / 10_000 * first_payment.percentage) |> Kernel.trunc()
        "#{currency_symbol}#{amount}.00 #{interval_text}"
      else
        "#{first_payment.price} #{interval_text}"
      end <> "#{count_text}"
    else
      nil
    end
  end

  defp get_subject_for_email(status, organization_name) when status in [:booked, :hidden],
    do: "Your session with #{organization_name} has been successfully rescheduled."

  defp get_subject_for_email(type, organization_name) when type in [:open, :reserved],
    do: "Booking your shoot with #{organization_name}"

  defp short_codes_values(key, data),
    do:
      BookingEventTemplates.body(key)
      |> Utils.render(data)
      |> Utils.normalize_body_template()

  defp client_first_name(job),
    do: Todoplace.Job.client(job) |> Map.get(:name) |> String.split() |> hd

  defp get_proposal_url(job),
    do:
      job
      |> Repo.preload([:booking_proposals])
      |> Map.get(:booking_proposals)
      |> hd()
      |> Map.get(:id)
      |> BookingProposal.url()

  def parse_time(time), do: time |> Timex.format("{h12}:{0m} {am}") |> elem(1)

  def migrated(booking_event) do
    booking_event_dates = BookingEvents.get_booking_event_dates(booking_event.id)

    migrated =
      Enum.any?(booking_event_dates) || is_nil(booking_event.old_dates) ||
        booking_event.old_dates == []

    if migrated, do: :migrated, else: :unmigrated
  end

  def check_external_slot_booked(slot, date, external_calendar_events, time_zone) do
    external_calendar_events
    |> Enum.any?(fn event ->
      external_event_overlap?(date, slot, event, time_zone)
    end)
  end

  def check_any_slot_booked_externally(slots, date, external_calendar_events, time_zone) do
    Enum.any?(slots, &check_external_slot_booked(&1, date, external_calendar_events, time_zone))
  end

  def get_external_events(%{assigns: %{booking_event: booking_event}} = socket) do
    %{nylas_detail: nylas_detail, time_zone: time_zone} =
      booking_event
      |> Repo.preload(organization: [user: :nylas_detail])
      |> Map.get(:organization)
      |> Map.get(:user)

    booking_with_dates = booking_event.dates |> Enum.reject(&is_nil(&1.date))
    empty? = booking_with_dates |> Enum.empty?()

    external_events =
      if nylas_detail.oauth_token && nylas_detail.external_calendar_rw_id &&
           !empty? do
        {%{date: first_date}, %{date: last_date}} =
          Enum.min_max_by(booking_with_dates, & &1.date, Date)

        start_date =
          DateTime.new!(first_date, ~T[00:00:00], time_zone)
          |> DateTime.to_unix()

        end_date =
          DateTime.new!(last_date, ~T[23:59:59], time_zone)
          |> DateTime.to_unix()

        {:ok, events} =
          NylasCalendar.get_events(
            nylas_detail.external_calendar_rw_id,
            nylas_detail.oauth_token,
            {start_date, end_date}
          )

        events
        |> Enum.reject(fn
          %{"description" => nil} -> true
          %{"description" => desc} -> String.contains?(desc, "[From Todoplace]")
        end)
        |> Enum.map(&to_datetime(&1, time_zone))
        |> Enum.reject(&is_nil(&1))
      end || []

    socket |> assign(external_events: external_events)
  end

  def remove_conflicting_slots(slots, _, [], _), do: slots
  def remove_conflicting_slots(slots, nil, _, _), do: slots

  def remove_conflicting_slots(slots, date, external_calendar_events, time_zone) do
    slots
    |> Enum.map(fn slot ->
      slot = is_changeset(slot)

      external_book? =
        external_calendar_events
        |> Enum.any?(fn event ->
          external_event_overlap?(date, slot, event, time_zone)
        end)

      if external_book? do
        %{slot | status: :external_booked}
      else
        slot
      end
    end)
  end

  def is_changeset(%Ecto.Changeset{} = slot), do: current(slot)
  def is_changeset(slot), do: slot

  def to_datetime(
        %{
          "when" => %{"start_time" => start_time, "end_time" => end_time, "object" => object}
        },
        timezone
      )
      when object in ["timespan", "time"] do
    %{
      start: from_unix(start_time, timezone),
      end: from_unix(end_time, timezone)
    }
  end

  def to_datetime(_, _), do: nil

  def from_unix(time, timezone) do
    time
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(timezone)
  end

  def external_event_overlap?(date, slot, event, time_zone) do
    start_datetime = DateTime.new!(date, slot.slot_start, time_zone)
    end_datetime = DateTime.new!(date, slot.slot_end, time_zone)

    DateTime.compare(end_datetime, event.start) in [:eq, :gt] &&
      DateTime.compare(start_datetime, event.end) in [:eq, :lt]
  end
end
