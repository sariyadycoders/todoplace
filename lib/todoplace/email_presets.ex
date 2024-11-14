defmodule Todoplace.EmailPresets do
  @moduledoc """
  Context to handle email presets
  """
  import Ecto.Query
  import Todoplace.Repo.CustomMacros

  alias Todoplace.{Repo, Job, Shoot, EmailPresets.EmailPreset, Utils}
  alias Todoplace.Galleries.Gallery

  @doc """
  Retrieves email automation presets for a specific type, job type, and pipeline.

  This function retrieves email automation presets that match the specified `type`, `job_type`,
  and `pipeline_id`. It returns a list of email automation presets that meet the criteria.

  ## Parameters

      - `type`: The type of email automation presets to retrieve, either `:gallery` or `:order`.
      - `job_type`: A value representing the job type for which email automation presets are retrieved.
      - `pipeline_id`: An integer representing the ID of the email automation pipeline.

  ## Returns

  A list of maps, each representing an email automation preset that matches the criteria.

  ## Example

      ```elixir
      # Retrieve email automation presets for a specific type, job type, and pipeline
      presets = Todoplace.EmailAutomations.email_automation_presets(:gallery, :job, 123)
  """
  def email_automation_presets(type, job_type, pipeline_id) do
    from(p in presets(type),
      where:
        p.job_type == ^job_type and is_nil(p.organization_id) and
          p.email_automation_pipeline_id == ^pipeline_id
    )
    |> Repo.all()
  end

  def user_email_automation_presets(type, job_type, pipeline_id, org_id) do
    from(p in presets(type),
      where:
        p.job_type == ^job_type and p.organization_id == ^org_id and
          p.email_automation_pipeline_id == ^pipeline_id
    )
    |> Repo.all()
  end

  def for(%Gallery{}, state) do
    from(preset in gallery_presets(), where: preset.state == ^state)
    |> Repo.all()
  end

  def for(%Job{type: job_type}, state) do
    from(preset in job_presets(), where: preset.job_type == ^job_type and preset.state == ^state)
    |> Repo.all()
  end

  def for(%Job{type: job_type, client: %{organization_id: organization_id}} = job) do
    job = job |> Repo.preload(:job_status)

    from(
      preset in job_presets(),
      where: preset.job_type == ^job_type and preset.organization_id == ^organization_id
    )
    |> for_job(job)
    |> Repo.all()
  end

  defp for_job(query, %Job{
         job_status: %{is_lead: true, current_status: current_status},
         id: job_id
       }) do
    state = if current_status == :not_sent, do: :lead, else: :manual_booking_proposal_sent

    from(preset in query,
      join: job in Job,
      on: job.type == preset.job_type and job.id == ^job_id,
      where: preset.state == ^state
    )
  end

  defp for_job(query, %Job{job_status: %{is_lead: false}, id: job_id}) do
    from(preset in query,
      join: job in Job,
      on: job.type == preset.job_type and job.id == ^job_id,
      join:
        shoot in subquery(
          from(shoot in Shoot,
            where: shoot.starts_at <= now() and shoot.job_id == ^job_id,
            select: %{past_count: count(shoot.id)}
          )
        ),
      on: true,
      where:
        (preset.state == :job and shoot.past_count == 0) or
          (preset.state == :post_shoot and shoot.past_count > 0)
    )
  end

  defp job_presets(), do: presets(:job)
  defp gallery_presets(), do: presets(:gallery)

  defp presets(type),
    do: from(preset in EmailPreset, where: preset.type == ^type, order_by: :position)

  def resolve_variables(%EmailPreset{} = preset, schemas, helpers) do
    resolver_module =
      if preset.type in [:job, :lead],
        do: Todoplace.EmailPresets.JobResolver,
        else: Todoplace.EmailPresets.GalleryResolver

    resolver = schemas |> resolver_module.new(helpers)

    data =
      for {key, func} <- resolver_module.vars(), into: %{} do
        {key, func.(resolver)}
      end

    %{
      preset
      | body_template:
          Utils.render(preset.body_template, data) |> Utils.normalize_body_template(),
        subject_template: Utils.render(preset.subject_template, data),
        short_codes: data
    }
  end
end
