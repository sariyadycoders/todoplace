defmodule Todoplace.Repo.Migrations.AddMaterialize do
  use Ecto.Migration

  @old_view """
  create or replace view job_statuses as (
    with proposal_statuses as (
      select
        job_id,
        case
          when questionnaire_answers.id is not null
          and booking_proposals.questionnaire_id is not null then 'answered'
          when signed_at is not null
          and booking_proposals.questionnaire_id is not null then 'signed_with_questionnaire'
          when signed_at is not null then 'signed_without_questionnaire'
          when accepted_at is not null then 'accepted'
          else 'sent'
        end as status,
        coalesce(
          questionnaire_answers.inserted_at,
          signed_at,
          accepted_at,
          booking_proposals.inserted_at
        ) as changed_at
      from
        booking_proposals
        left join questionnaire_answers on questionnaire_answers.proposal_id = booking_proposals.id
    ), payments as (
      select distinct on (job_id) job_id, paid_at, is_with_cash
      from payment_schedules
      where paid_at is not null or is_with_cash is true
      order by job_id, paid_at, is_with_cash
    )
    select
      jobs.id as job_id,
      case
        when jobs.archived_at is not null then 'archived'
        when jobs.completed_at is not null then 'completed'
        when jobs.is_gallery_only is true then 'imported'
        when packages.collected_price is not null then 'imported'
        when payments.paid_at is not null then 'deposit_paid'
        else coalesce(proposal_statuses.status, 'not_sent')
      end as current_status,
      coalesce(proposal_statuses.changed_at, jobs.archived_at, jobs.completed_at, jobs.inserted_at) as changed_at,
      case
      when is_with_cash is true then false
      when is_gallery_only is true then false
      when paid_at is null and collected_price is null then true
    else false
  end as is_lead
    from
      jobs
      left join proposal_statuses on proposal_statuses.job_id = jobs.id
      left join payments on payments.job_id = jobs.id
      left join packages on packages.id = jobs.package_id
  )
  """

  @new_view """
  create materialized view job_statuses as (
    with proposal_statuses as (
      select
        job_id,
        case
          when questionnaire_answers.id is not null
          and booking_proposals.questionnaire_id is not null then 'answered'
          when signed_at is not null
          and booking_proposals.questionnaire_id is not null then 'signed_with_questionnaire'
          when signed_at is not null then 'signed_without_questionnaire'
          when accepted_at is not null then 'accepted'
          else 'sent'
        end as status,
        coalesce(
          questionnaire_answers.inserted_at,
          signed_at,
          accepted_at,
          booking_proposals.inserted_at
        ) as changed_at
      from
        booking_proposals
        left join questionnaire_answers on questionnaire_answers.proposal_id = booking_proposals.id
    ), payments as (
      select distinct on (job_id) job_id, paid_at, is_with_cash
      from payment_schedules
      where paid_at is not null or is_with_cash is true
      order by job_id, paid_at, is_with_cash
    )
    select
      jobs.id as job_id,
      case
        when jobs.archived_at is not null then 'archived'
        when jobs.completed_at is not null then 'completed'
        when jobs.is_gallery_only is true then 'imported'
        when packages.collected_price is not null then 'imported'
        when payments.paid_at is not null then 'deposit_paid'
        else coalesce(proposal_statuses.status, 'not_sent')
      end as current_status,
      coalesce(proposal_statuses.changed_at, jobs.archived_at, jobs.completed_at, jobs.inserted_at) as changed_at,
      case
      when is_with_cash is true then false
      when is_gallery_only is true then false
      when paid_at is null and collected_price is null then true
    else false
  end as is_lead
    from
      jobs
      left join proposal_statuses on proposal_statuses.job_id = jobs.id
      left join payments on payments.job_id = jobs.id
      left join packages on packages.id = jobs.package_id
  );
  """

  @function """
  create or replace function refresh_job_statuses()
  returns trigger as $$
  begin
    refresh materialized view job_statuses;
    return null;
  end;
  $$ language plpgsql;
  """

  def up do
    execute("drop view job_statuses")
    execute(@new_view)
    execute(@function)

    execute("""
    create trigger refresh_questionnaire_answers_trg
    after insert or update or delete on questionnaire_answers
    for each statement
    execute procedure refresh_job_statuses();
    """)

    execute("""
    create trigger refresh_jobs_trg
    after insert or update or delete on jobs
    for each statement
    execute procedure refresh_job_statuses();
    """)

    execute("""
    create trigger refresh_packages_trg
    after insert or update or delete on packages
    for each statement
    execute procedure refresh_job_statuses();
    """)

    execute("""
    create trigger refresh_proposals_trg
    after insert or update or delete on booking_proposals
    for each statement
    execute procedure refresh_job_statuses();
    """)

    execute("""
    create trigger refresh_payment_schedules_trg
    after insert or update or delete on payment_schedules
    for each statement
    execute procedure refresh_job_statuses();
    """)
  end

  def down do
    execute("drop trigger refresh_jobs_trg on jobs")
    execute("drop trigger refresh_packages_trg on packages")
    execute("drop trigger refresh_questionnaire_answers_trg on questionnaire_answers")
    execute("drop trigger refresh_proposals_trg on booking_proposals")
    execute("drop trigger refresh_payment_schedules_trg on payment_schedules")
    execute("drop function refresh_job_statuses")
    execute("drop materialized view job_statuses")

    execute(@old_view)
  end
end
