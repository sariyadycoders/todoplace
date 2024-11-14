defmodule TodoplaceWeb.ClientBookingEventLive.Shared do
  @moduledoc """
  functions used by client booking events
  """
  import TodoplaceWeb.LiveHelpers
  import Phoenix.Component
  import TodoplaceWeb.Gettext, only: [ngettext: 3]

  def blurred_thumbnail(assigns) do
    ~H"""
      <div class={"aspect-[6/4] flex items-center justify-center relative overflow-hidden #{@class}"}>
        <div class="absolute inset-0 bg-center bg-cover bg-no-repeat blur-lg" style={"background-image: url('#{@url}')"} />
        <img class="h-full object-cover relative" src={@url} />
      </div>
    """
  end

  def date_display(assigns) do
    ~H"""
      <div class="flex items-center">
        <.icon name="calendar" class="w-5 h-5 text-black" />
        <span class="ml-2 pt-1"><%= @date %></span>
      </div>
    """
  end

  def address_display(assigns) do
    assigns = Enum.into(assigns, %{class: ""})

    ~H"""
      <div class={"flex items-center #{@class}"}>
      <div class="w-5">
         <%!-- This div is compulsory to maintain aspect ratio of icon --%>
           <div>
           <.icon name="pin" class="w-5 h-5 text-black" />
           </div>
         </div>
          <div class="ml-2 pt-1"><%= if @booking_event.address, do: @booking_event.address, else: "Event location not set" %></div>
      </div>
    """
  end

  def subtitle_display(assigns) do
    ~H"""
      <p class={@class}><%= formatted_subtitle(@booking_event, @package) %></p>
    """
  end

  def formatted_date(%{dates: dates}) do
    dates
    |> Enum.sort_by(& &1.date, Date)
    |> Enum.reduce([], fn date, acc ->
      case acc do
        [] ->
          [[date]]

        [prev_chunk | rest] ->
          case Date.add(List.last(prev_chunk).date, 1) == date.date do
            true -> [prev_chunk ++ [date] | rest]
            false -> [[date] | acc]
          end
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn chunk ->
      if Enum.count(chunk) > 1 do
        "#{format_date(List.first(chunk).date)} - #{format_date(List.last(chunk).date)}"
      else
        format_date(List.first(chunk).date)
      end
    end)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  def date_and_address_display(%{start_date: start_date, end_date: end_date} = assigns) do
    display_date =
      cond do
        Map.get(assigns, :skip_date, false) ->
          start_date

        is_nil(start_date) and is_nil(end_date) ->
          ""

        Date.compare(start_date, end_date) in [:gt, :lt] ->
          "#{date_formatter(start_date)} - #{date_formatter(end_date)}"

        Date.compare(start_date, end_date) == :eq ->
          date_formatter(start_date)
      end

    assigns = assigns |> Enum.into(%{display_date: display_date})

    ~H"""
      <div class="flex items-start">
        <div class="mt-2">
          <div class="w-5 h-5 text-black">
            <.icon name="calendar_and_location" class="w-5 h-5 text-black" />
          </div>
        </div>
        <div class="ml-2 pt-1 text-base-250 break-words">
          <div class="break-words">
            <%= @display_date %>
          </div>
          <div class="break-words">
            <%= @address %>
          </div>
        </div>
      </div>
    """
  end

  def group_date_address(event_dates) do
    event_dates =
      event_dates
      |> Enum.group_by(& &1.address)
      |> Enum.map(fn {address, booking_dates} ->
        booking_dates = booking_dates |> Enum.reject(&is_nil(&1.date))

        if Enum.empty?(booking_dates) do
          %{address: address, start_date: nil, end_date: nil}
        else
          {%{date: start_date}, %{date: end_date}} =
            Enum.min_max_by(booking_dates, & &1.date, Date)

          %{address: address, start_date: start_date, end_date: end_date}
        end
      end)

    without_dates = Enum.filter(event_dates, &is_nil(&1.start_date))

    with_dates =
      Enum.reject(event_dates, &is_nil(&1.start_date))
      |> Enum.sort_by(& &1.start_date, {:asc, Date})

    without_dates ++ with_dates
  end

  def session_info(%{dates: dates}) do
    session_list =
      dates
      |> Enum.map(& &1.session_length)
      |> Enum.sort()
      |> Enum.uniq()

    if length(session_list) > 1,
      do: "#{List.first(session_list)} - #{List.last(session_list)}",
      else: "#{List.first(session_list)}"
  end

  def maybe_event_disable_or_archive(%{assigns: %{booking_event: booking_event}} = socket) do
    status = Map.get(booking_event, :status)

    case status do
      :active ->
        socket

      status ->
        socket
        |> TodoplaceWeb.ConfirmationComponent.open(%{
          title:
            "Your reservation has #{status}. Contact your photographer for more information.",
          icon: "warning-orange"
        })
    end
    |> assign(status: status)
  end

  defp format_date(date),
    do: "#{capitalize_month(Calendar.strftime(date, "%b"))} #{Calendar.strftime(date, "%d, %Y")}"

  defp capitalize_month(month), do: String.capitalize(to_string(month))

  defp formatted_subtitle(_booking_event, %{download_count: count} = _package) do
    [
      if(count > 0,
        do: "#{count} #{ngettext("image", "images", count)}"
      )
      # "#{booking_event.duration_minutes} min session",
      # dyn_gettext(booking_event.location)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" | ")
  end
end
