defmodule Todoplace.Repo.Migrations.UpdateOrganizationJobTypesWithNewJobTypes do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]
  alias Todoplace.{Repo, JobType}

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    organizations = from("organizations", select: [:id, :profile]) |> Repo.all()
    job_types = from(jt in JobType, select: %{name: jt.name}) |> Repo.all()

    Enum.map(organizations, fn org ->
      existing_job_types =
        from(ojt in "organization_job_types",
          where: ojt.organization_id == ^org.id,
          select: %{name: ojt.job_type}
        )
        |> Repo.all()

      new_job_types = job_types -- existing_job_types

      Enum.map(new_job_types, fn type ->
        # selected? = if type.name in existing_job_types, do: true, else: false

        execute("""
          INSERT INTO organization_job_types ("show_on_profile?", "show_on_business?", organization_id, job_type, inserted_at, updated_at) VALUES (false, false, #{org.id}, '#{type.name}', '#{now}', '#{now}');
        """)
      end)
    end)
  end

  def down do
    execute("""
    delete from organization_job_types where job_type = 'senior'
    """)

    execute("""
    delete from organization_job_types where job_type = 'pets'
    """)

    execute("""
    delete from organization_job_types where job_type = 'sports'
    """)

    execute("""
    delete from organization_job_types where job_type = 'cake_smash'
    """)

    execute("""
    delete from organization_job_types where job_type = 'birth'
    """)

    execute("""
    delete from organization_job_types where job_type = 'branding'
    """)
  end
end
