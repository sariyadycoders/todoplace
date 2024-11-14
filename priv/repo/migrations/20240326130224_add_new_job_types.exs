defmodule Todoplace.Repo.Migrations.AddNewJobTypes do
  use Ecto.Migration
  import Ecto.Query
  alias Todoplace.{Package, Repo, Job}
  def up do
    execute("""
    insert into job_types (name, position) values ('senior', 10)
    """)
    execute("""
    insert into job_types (name, position) values ('pets', 11)
    """)
    execute("""
    insert into job_types (name, position) values ('sports', 12)
    """)
    execute("""
    insert into job_types (name, position) values ('cake_smash', 13)
    """)
    execute("""
    insert into job_types (name, position) values ('birth', 14)
    """)
    execute("""
    insert into job_types (name, position) values ('branding', 15)
    """)

    flush()

    if System.get_env("MIX_ENV") != "prod" do
      Mix.Tasks.ImportQuestionnaires.questionnaires(%{state: :change_to_global})
      Mix.Tasks.InsertGlobalSettings.global_settings()
    end
  end

  def down do
    # Get all packages with new job_types
    packages_with_new_job_types =
      from(p in Package,
        where: p.job_type in ["senior", "pets", "sports", "cake_smash", "birth", "branding"]
      )
      |> Repo.all()
    Enum.map(packages_with_new_job_types, fn package ->
      # Delete jobs related to packages with new job_type
      execute("""
      delete from jobs where package_id = #{package.id}
      """)
      # Delete package_payment_schedules related to packages with new job_type
      execute("""
      delete from package_payment_schedules where package_id = #{package.id}
      """)
      # Delete packages created with new job_type
      execute("""
      delete from packages where id = #{package.id}
      """)
    end)
    # Get all jobs creaated with new job_types
    jobs_with_new_job_types =
      from(j in Job,
        where: j.type in ["senior", "pets", "sports", "cake_smash", "birth", "branding"]
      )
      |> Repo.all()
    Enum.map(jobs_with_new_job_types, fn job ->
      # Delete payment_schedules related to job with new job_types
      execute("""
      delete from payment_schedules where job_id = #{job.id}
      """)
      # Delete shoots related to job with new job_types
      execute("""
      delete from shoots where job_id = #{job.id}
      """)
      # Delete email_schedules related to job with new job_types
      execute("""
      delete from email_schedules where job_id = #{job.id}
      """)
      # Delete jobs created with new job_types
      execute("""
      delete from jobs where id = #{job.id}
      """)
    end)
    # Delete email_presets created with new job_types
    execute("""
    delete from email_presets where job_type in ('senior', 'pets', 'sports', 'cake_smash', 'birth', 'branding')
    """)
    # Delete questionnaires created with new job_types
    execute("""
    delete from questionnaires where job_type in ('senior', 'pets', 'sports', 'cake_smash', 'birth', 'branding')
    """)
    execute("""
    delete from job_types where name = 'senior'
    """)
    execute("""
    delete from job_types where name = 'pets'
    """)
    execute("""
    delete from job_types where name = 'sports'
    """)
    execute("""
    delete from job_types where name = 'cake_smash'
    """)
    execute("""
    delete from job_types where name = 'birth'
    """)
    execute("""
    delete from job_types where name = 'branding'
    """)
  end
end