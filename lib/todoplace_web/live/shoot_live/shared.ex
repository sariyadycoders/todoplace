defmodule TodoplaceWeb.ShootLive.Shared do
  @moduledoc """
  handlers used by job shoots and booking events
  """
  alias Todoplace.Shoot
  import TodoplaceWeb.Gettext, only: [dyn_gettext: 1]
  import TodoplaceWeb.LiveHelpers
  import TodoplaceWeb.FormHelpers
  use Phoenix.Component

  def duration_options() do
    for(duration <- Shoot.durations(), do: {dyn_gettext("duration-#{duration}"), duration})
  end

  def location(assigns) do
    assigns =
      assigns
      |> assign_new(:allow_location_toggle, fn -> true end)
      |> assign_new(:allow_address_toggle, fn -> true end)
      |> assign_new(:address_field_title, fn -> "Shoot Address" end)
      |> assign_new(:location_field_title, fn -> "Shoot Location" end)
      |> assign_new(:is_edit, fn -> true end)

    ~H"""
    <%= if @allow_location_toggle do %>
      <div class={classes("flex flex-col", %{"sm:col-span-3" => !@address_field, "sm:col-span-2" => @address_field} |> Map.merge(select_invalid_classes(@f, :location)))}>

        <div class="flex flex-col justify-between">
          <div class="flex justify-between items-center">
            <%= label_for @f, :location, label: @location_field_title %>
            <%= if @allow_address_toggle && !@address_field do %>
              <a class="text-xs link" phx-target={@myself} phx-click="address" phx-value-action="add-field" {testid("add-address")}>Add an address</a>
            <% end %>
          </div>
          <%= select_field @f, :location, for(location <- Shoot.locations(), do: {location |> Atom.to_string() |> dyn_gettext(), location }), prompt: "Select below",  disabled: !@is_edit  %>
        </div>
      </div>
    <% end %>

    <%= if @address_field do %>
      <div class="flex flex-col sm:col-span-2">
        <div class="flex items-center justify-between">
          <%= label_for @f, :address, label: @address_field_title %>
          <%= if @allow_address_toggle do %>
            <a class="text-xs link" phx-target={@myself} phx-click="address" phx-value-action="remove">Remove address</a>
          <% end %>
        </div>
        <%= input @f, :address, phx_hook: "PlacesAutocomplete", autocomplete: "off", placeholder: "Enter a location", data_event_name: "place_changed", data_target: @myself, disabled: !@is_edit %>
        <div class="relative autocomplete-wrapper" id="auto-complete" phx-update="ignore"></div>
      </div>
    <% end %>
    """
  end

  def parse_shoot_time_zone(starts_at, time_zone) do
    if is_tz_date?(starts_at) do
      {:ok, converted_date} = NaiveDateTime.from_iso8601(starts_at)

      converted_date
    else
      case parse_in_zone(starts_at, time_zone) do
        {:ok, datetime} -> datetime
        _ -> nil
      end
    end
  end

  defp parse_in_zone("" <> str, zone) do
    with {:ok, naive_datetime} <- NaiveDateTime.from_iso8601(str <> ":00") do
      DateTime.from_naive(naive_datetime, zone)
    end
  end

  defp is_tz_date?(date) do
    case DateTime.from_iso8601(date) do
      {:ok, _, _} -> true
      _ -> false
    end
  end
end
