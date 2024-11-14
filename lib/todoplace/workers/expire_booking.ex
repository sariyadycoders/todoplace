defmodule Todoplace.Workers.ExpireBooking do
  @moduledoc "Background job to expire a lead created from a booking event"

  use Oban.Worker, unique: [fields: [:args, :worker]]
  alias Todoplace.{BookingEvents}

  def perform(%Oban.Job{args: params}) do
    BookingEvents.expire_booking(params)
  end
end
