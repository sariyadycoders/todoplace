defmodule Todoplace.Repo.Migrations.UpdateBookingProposalEmailName do
  use Ecto.Migration
  import Ecto.Query

  alias Todoplace.{
    Repo,
    EmailAutomation.EmailScheduleHistory,
    EmailPresets.EmailPreset,
    EmailAutomation.EmailSchedule,
    EmailAutomation.EmailAutomationPipeline,
    EmailAutomation.EmailAutomationSubCategory,
    EmailAutomations
  }

  def change do
    pipeline = EmailAutomations.get_pipeline_by_state(:manual_booking_proposal_sent)

    from(e in EmailScheduleHistory, where: e.email_automation_pipeline_id == ^pipeline.id)
    |> Repo.update_all(set: [name: "Individual Booking Proposal Email"])

    from(e in EmailSchedule, where: e.email_automation_pipeline_id == ^pipeline.id)
    |> Repo.update_all(set: [name: "Individual Booking Proposal Email"])

    from(e in EmailPreset, where: e.email_automation_pipeline_id == ^pipeline.id)
    |> Repo.update_all(set: [name: "Individual Booking Proposal Email"])

    from(e in EmailAutomationPipeline, where: e.id == ^pipeline.id)
    |> Repo.update_all(set: [name: "Individual Booking Proposal and Follow Up Emails"])

    from(e in EmailAutomationSubCategory, where: e.slug == "booking_proposal")
    |> Repo.update_all(set: [name: "Individual Booking proposal"])
  end
end
