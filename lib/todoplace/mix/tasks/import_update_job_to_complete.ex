defmodule Mix.Tasks.ImportUpdateJobToComplete do
  @moduledoc false

  use Mix.Task
  require Logger
  import Ecto.Query

  alias Todoplace.{
    Repo,
    Job,
    Accounts.User
  }

  @shortdoc "Marked jobs as complete for those who have all payments have been received, and all shoots took place more than 4 weeks ago."
  def run(_) do
    load_app()

    from(o in Todoplace.Organization, select: %{id: o.id})
    |> Repo.all()
    |> Enum.map(fn org ->
      user = %User{organization_id: org.id}

      jobs =
        user
        |> Job.for_user()
        |> Job.not_leads()
        |> select_jobs()

      Enum.map(jobs, fn job ->
        if all_job_paid?(job) and !any_shoots_before(job) do
          job |> Job.complete_changeset() |> Repo.update()
        end
      end)
    end)
  end

  defp select_jobs(query) do
    from(j in query, preload: [:job_status, :shoots, :payment_schedules])
    |> Repo.all()
    |> Enum.filter(&(is_nil(&1.archived_at) and is_nil(&1.completed_at)))
  end

  defp all_job_paid?(%Job{payment_schedules: payment_schedules}) do
    if Enum.empty?(payment_schedules) do
      false
    else
      payment_schedules
      |> Enum.all?(fn p -> not is_nil(p.paid_at) end)
    end
  end

  defp any_shoots_before(%Job{shoots: shoots}) do
    if Enum.empty?(shoots) do
      true
    else
      Enum.any?(shoots, &(Date.diff(&1.starts_at |> Timex.shift(weeks: 4), Timex.now()) < 0))
    end
  end

  defp load_app do
    if System.get_env("MIX_ENV") != "prod" do
      Mix.Task.run("app.start")
    end
  end
end
