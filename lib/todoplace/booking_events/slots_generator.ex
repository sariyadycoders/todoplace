defmodule Todoplace.SlotGenerator do
  @moduledoc false
  alias Todoplace.{
    BookingEventDate.SlotBlock
  }

  def generate_and_filter_slots(start_time, end_time, session, session_gap) do
    generate_slots(start_time, end_time, session, session_gap)
    |> Enum.reject(&(Time.compare(&1.slot_end, end_time) == :gt))
  end

  def generate_slots(start_time, end_time, _session, _session_gap)
      when is_nil(start_time) or is_nil(end_time),
      do: []

  def generate_slots(_start_time, _end_time, nil, _session_gap), do: []

  def generate_slots(start_time, end_time, session_length, session_gap) do
    generate_slots(start_time, start_time, end_time, session_length, session_gap, [])
  end

  defp generate_slots(start_time, current_time, end_time, session_length, session_gap, acc) do
    cond do
      Time.compare(current_time, end_time) in [:gt, :eq] and
          Time.compare(current_time, start_time) in [:gt, :eq] ->
        Enum.reverse(acc)

      session_gap == nil and Time.compare(current_time, end_time) == :lt and
          Time.compare(current_time, start_time) in [:gt, :eq] ->
        next_end = Time.add(current_time, session_length * 60)

        if next_end > start_time do
          generate_slots(start_time, next_end, end_time, session_length, nil, [
            %SlotBlock{slot_start: current_time, slot_end: next_end} | acc
          ])
        else
          Enum.reverse(acc)
        end

      Time.compare(current_time, end_time) == :lt and
        Time.compare(current_time, start_time) in [:gt, :eq] and session_gap != nil ->
        generate_slots_acc(start_time, current_time, end_time, session_length, session_gap, acc)

      true ->
        Enum.reverse(acc)
    end
  end

  defp generate_slots_acc(start_time, current_time, end_time, session_length, session_gap, acc) do
    next_end = Time.add(current_time, session_length * 60)
    next_start = Time.add(next_end, session_gap * 60)

    slots_acc =
      if Time.diff(end_time, current_time, :minute) < session_length,
        do: acc,
        else: [%SlotBlock{slot_start: current_time, slot_end: end_time} | acc]

    if Time.compare(next_end, end_time) in [:lt, :eq] and
         Time.compare(next_end, start_time) in [:gt, :eq] do
      slots_acc =
        if Time.diff(next_end, current_time, :minute) < session_length,
          do: acc,
          else: [%SlotBlock{slot_start: current_time, slot_end: next_end} | acc]

      generate_slots(start_time, next_start, end_time, session_length, session_gap, slots_acc)
    else
      Enum.reverse(slots_acc)
    end
  end
end
