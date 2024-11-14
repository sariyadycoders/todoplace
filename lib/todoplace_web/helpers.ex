defmodule TodoplaceWeb.Helpers do
  @moduledoc "This module is used to define functions that can be accessed outside *Web"
  alias TodoplaceWeb.Endpoint
  alias TodoplaceWeb.Router.Helpers, as: Routes
  alias Todoplace.Cart.Order
  alias Todoplace.Galleries

  def booking_events_url(), do: Routes.calendar_booking_events_index_url(Endpoint, :index)

  def jobs_url(), do: Routes.job_url(Endpoint, :jobs)

  def job_url(id), do: Routes.job_url(Endpoint, :jobs, id)

  def invoice_url(job_id, proposal_id),
    do: Routes.job_download_url(Endpoint, :download_invoice_pdf, job_id, proposal_id)

  def lead_url(id), do: Routes.job_url(Endpoint, :leads, id)

  def inbox_thread_url(id), do: Routes.inbox_url(Endpoint, :show, "job-#{id}", type: "all")

  def gallery_url("" <> hash),
    do: Routes.gallery_client_index_url(Endpoint, :index, hash)

  def gallery_url(%{client_link_hash: hash}),
    do: Routes.gallery_client_index_url(Endpoint, :index, hash)

  def order_url(%{client_link_hash: hash, password: password}, order),
    do:
      Routes.gallery_client_order_url(Endpoint, :show, hash, Order.number(order),
        pw: password,
        email: Galleries.get_gallery_client_email(order)
      )

  def proofing_album_selections_url(%{client_link_hash: hash}, %{password: password}, order),
    do:
      Routes.gallery_client_order_url(Endpoint, :proofing_album, hash, Order.number(order),
        pw: password,
        email: Galleries.get_gallery_client_email(order)
      )

  def album_url("" <> hash), do: Routes.gallery_client_album_url(Endpoint, :proofing_album, hash)

  def profile_pricing_job_type_url(slug, type),
    do:
      Endpoint
      |> Routes.profile_url(:index, slug)
      |> URI.parse()
      |> Map.put(:fragment, type)
      |> URI.to_string()

  def client_booking_event_url(_slug, nil), do: nil

  def client_booking_event_url(slug, id) do
    Endpoint
    |> Routes.client_booking_event_url(:show, slug, id)
  end

  def ngettext(singular, plural, count) do
    Gettext.dngettext(TodoplaceWeb.Gettext, "todoplace", singular, plural, count, %{})
  end

  def days_distance(%DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> days_distance()

  def days_distance(%Date{} = date), do: date |> Date.diff(Date.utc_today())

  defdelegate strftime(zone, date, format), to: TodoplaceWeb.LiveHelpers

  defdelegate dyn_gettext(key), to: TodoplaceWeb.Gettext

  defdelegate shoot_location(shoot), to: TodoplaceWeb.LiveHelpers
end
