defmodule Todoplace.Shoots do
  @moduledoc false

  alias Todoplace.{Repo, Shoot, Job, NylasCalendar}
  import Ecto.Query
  require Logger

  def get_shoots(user, %{"start" => start_date, "end" => end_date}) do
    from([shoot, job, client, status] in get_by_user_query(user),
      where: shoot.starts_at >= ^start_date and shoot.starts_at <= ^end_date,
      select: {shoot, job, client, status},
      order_by: shoot.starts_at
    )
    |> Repo.all()
  end

  def get_by_user_query(user) do
    from(shoot in Shoot,
      join: job in assoc(shoot, :job),
      join: client in assoc(job, :client),
      join: status in assoc(job, :job_status),
      where:
        client.organization_id == ^user.organization_id and
          is_nil(job.archived_at) and
          (status.is_lead == false or is_nil(job.booking_event_id))
    )
  end

  def has_external_event_query(query),
    do: where(query, [shoot], not is_nil(shoot.external_event_id))

  def get_shoot(shoot_id), do: Repo.get(Shoot, shoot_id)

  def load_user(shoot),
    do: Repo.preload(shoot, job: [client: [organization: [user: :nylas_detail]]])

  def get_shoots_for_booking_event(
        %{organization_id: organization_id, time_zone: time_zone},
        beginning_of_day,
        end_of_day_with_buffer
      ) do
    from(shoot in Shoot,
      join: job in assoc(shoot, :job),
      join: client in assoc(job, :client),
      where:
        client.organization_id == ^organization_id and is_nil(job.archived_at) and
          is_nil(job.completed_at),
      where: shoot.starts_at >= ^beginning_of_day and shoot.starts_at <= ^end_of_day_with_buffer
    )
    |> Repo.all()
    |> Repo.preload(job: [:client])
    |> Enum.map(fn shoot ->
      Map.merge(
        shoot,
        %{
          start_time: shoot.starts_at |> DateTime.shift_zone!(time_zone),
          end_time:
            shoot.starts_at
            |> DateTime.add(shoot.duration_minutes * 60)
            |> DateTime.shift_zone!(time_zone)
        }
      )
    end)
  end

  def get_next_shoot(%Job{shoots: shoots}) when is_nil(shoots), do: nil

  def get_next_shoot(%Job{shoots: shoots}) do
    shoots
    |> Enum.filter(&(&1.starts_at >= DateTime.utc_now()))
    |> List.first()
  end

  def get_next_shoot(%Job{} = job) do
    job.id
    |> Shoot.for_job()
    |> Repo.all()
    |> Enum.filter(&(&1.starts_at >= DateTime.utc_now()))
    |> List.first()
  end

  def get_latest_shoot(job_id) do
    Shoot
    |> where([s], s.job_id == ^job_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def broadcast_shoot_change(%Shoot{} = shoot) do
    job = shoot |> Repo.preload(job: :client) |> Map.get(:job)

    Phoenix.PubSub.broadcast(
      Todoplace.PubSub,
      topic_shoot_change(job.client.organization_id),
      {:shoot_updated, shoot}
    )
  end

  def subscribe_shoot_change(organization_id),
    do: Phoenix.PubSub.subscribe(Todoplace.PubSub, topic_shoot_change(organization_id))

  def create_event(shoot) do
    {params, token} = map_event(shoot, :insert)

    case NylasCalendar.create_event(params, token) do
      {:ok, %{"id" => id}} ->
        shoot
        |> Shoot.create_booking_event_shoot_changeset(%{external_event_id: id})
        |> Repo.update!()

        Logger.info("Event created for shoot_id: #{shoot.id}")

      error ->
        Sentry.capture_message("Error #{inspect(error)}")
        Logger.error("Error #{inspect(error)}")
    end
  end

  def map_event(%{job: %{client: %{organization: %{user: user}}}} = shoot, action) do
    nylas_detail = user.nylas_detail

    {Shoot.map_event(shoot, nylas_detail, action), nylas_detail.oauth_token}
  end

  defp topic_shoot_change(organization_id), do: "shoot_change:#{organization_id}"
end
