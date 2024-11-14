defmodule TodoplaceWeb.ICalendarController do
  use TodoplaceWeb, :controller

  alias Todoplace.{Accounts, Shoots, Repo, Job}

  import TodoplaceWeb.Helpers, only: [job_url: 1, lead_url: 1]
  
  use PhoenixSwagger

  swagger_path :index do
    get "/calendar/{token}"
    description "Retrieve calendar events in iCalendar format"
    response 200, "Success", :ICalendarResponse
    response 404, "Unauthorized"
  end
  def index(conn, %{"token" => token}) do
    case Phoenix.Token.verify(conn, "USER_ID", token, max_age: :infinity) do
      {:ok, user_id} ->
        user = Accounts.get_user!(user_id) |> Repo.preload(:organization)

        params = %{
          "start" => DateTime.utc_now(),
          "end" => DateTime.utc_now() |> DateTime.add(2 * 365 * 24 * 60 * 60)
        }

        events = Shoots.get_shoots(user, params) |> map(user)

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, %ICalendar{events: events} |> ICalendar.to_ics())

      {:error, _} ->
        conn
        |> put_flash(:error, "Unauthorized")
        |> redirect(to: "/")
    end
  end

  defp map(feeds, user) do
    feeds
    |> Enum.map(fn {shoot, job, client, status} ->
      url = if status.is_lead, do: job_url(job.id), else: lead_url(job.id)

      start_date =
        shoot.starts_at
        |> DateTime.shift_zone!(user.time_zone)

      end_date =
        shoot.starts_at
        |> DateTime.add(shoot.duration_minutes * 60)
        |> DateTime.shift_zone!(user.time_zone)

      title = "#{Job.name(Map.put(job, :client, client))} - #{shoot.name}"

      %ICalendar.Event{
        summary: title,
        dtstart: start_date,
        dtend: end_date,
        description: shoot.notes,
        organizer: user.email,
        uid: "shoot_#{shoot.id}@todoplace.com",
        attendees: [
          %{
            "PARTSTAT" => "ACCEPTED",
            "CN" => user.email,
            original_value: "mailto:#{user.email}"
          }
        ],
        url: url,
        location: shoot.address || shoot.location |> Atom.to_string() |> dyn_gettext()
      }
    end)
  end

  def swagger_definitions do
    %{
      ICalendarResponse: swagger_schema do
        title "ICalendar Response"
        description "Response schema for iCalendar data"
        example """
          BEGIN:VCALENDAR
          CALSCALE:GREGORIAN
          VERSION:2.0
          PRODID:-//Elixir ICalendar//Elixir ICalendar//EN
          BEGIN:VEVENT
          DESCRIPTION:Let's go see Star Wars.
          DTEND:20151224T084500
          DTSTART:20151224T083000
          LOCATION:123 Fun Street\\, Toronto ON\\, Canada
          SUMMARY:Film with Amy and Adam
          END:VEVENT
          BEGIN:VEVENT
          DESCRIPTION:A big long meeting with lots of details.
          DTEND:20240806T191722Z
          DTSTART:20240806T161722Z
          LOCATION:456 Boring Street\\, Toronto ON\\, Canada
          SUMMARY:Morning meeting
          END:VEVENT
          END:VCALENDAR
        """
        type :string
      end
    }
  end
end
