defmodule TodoplaceWeb.PDFView do
  use TodoplaceWeb, :html
  alias Todoplace.{PaymentSchedules}

  import TodoplaceWeb.BookingProposalLive.ScheduleComponent,
    only: [make_status: 1, status_class: 1]
end
