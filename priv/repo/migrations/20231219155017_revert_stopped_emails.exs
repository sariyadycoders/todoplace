defmodule Todoplace.Repo.Migrations.RevertStoppedEmails do
  use Ecto.Migration

  alias Todoplace.{
    Repo,
    EmailAutomation.EmailScheduleHistory,
    EmailAutomationSchedules,
    EmailAutomations
  }

  import Ecto.Query

  def change do
    pipeline = EmailAutomations.get_pipeline_by_state(:manual_booking_proposal_sent)

    schedule_history_query =
      from(esh in EmailScheduleHistory,
        where:
          esh.job_id == 9114 and esh.email_automation_pipeline_id == ^pipeline.id and
            esh.stopped_reason == :proposal_accepted
      )

    EmailAutomationSchedules.pull_back_email_schedules_multi(schedule_history_query)
    |> Repo.transaction()
  end
end
