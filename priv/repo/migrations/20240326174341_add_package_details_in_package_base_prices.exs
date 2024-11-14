defmodule Todoplace.Repo.Migrations.AddPackageDetailsInPackageBasePrices do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]
  alias Todoplace.{Repo, Packages.BasePrice}

  def up do
    # Fetch portrait package base price details
    portrait_packages = from(bp in BasePrice, where: bp.job_type == "portrait") |> Repo.all()

    # New job types which we have to duplicate portrait package base price details
    new_job_types = ["senior", "pets", "sports", "cake_smash"]

    # Duplicate portrait package base price details for ["senior", "pets", "sports", "cake_smash"] job_type
    Enum.map(new_job_types, fn job_type ->
      Enum.map(portrait_packages, fn package ->
        execute("""
          INSERT INTO package_base_prices ("base_price", "download_count", "full_time", "job_type", "min_years_experience",
          "shoot_count", "max_session_per_year", "tier", "turnaround_weeks")
          VALUES ('{"amount": #{package.base_price.amount}, "currency": "#{Atom.to_string(package.base_price.currency)}"}',
          #{package.download_count}, #{package.full_time}, '#{job_type}', #{package.min_years_experience}, #{package.shoot_count},
          #{package.max_session_per_year}, '#{package.tier}', #{package.turnaround_weeks});
        """)
      end)
    end)

    # Fetch wedding package base price details
    wedding_packages = from(bp in BasePrice, where: bp.job_type == "wedding") |> Repo.all()

    # Duplicate wedding package base price details for "birth" job_type
    Enum.map(wedding_packages, fn package ->
      execute("""
        INSERT INTO package_base_prices ("base_price", "download_count", "full_time", "job_type", "min_years_experience",
        "shoot_count", "max_session_per_year", "tier", "turnaround_weeks")
        VALUES ('{"amount": #{package.base_price.amount}, "currency": "#{Atom.to_string(package.base_price.currency)}"}',
        #{package.download_count}, #{package.full_time}, 'birth', #{package.min_years_experience}, #{package.shoot_count},
        #{package.max_session_per_year}, '#{package.tier}', #{package.turnaround_weeks});
      """)
    end)

    # Fetch global package base price details
    global_packages = from(bp in BasePrice, where: bp.job_type == "global") |> Repo.all()

    # Duplicate global package base price details for "branding" job_type
    Enum.map(global_packages, fn package ->
      execute("""
        INSERT INTO package_base_prices ("base_price", "download_count", "full_time", "job_type", "min_years_experience",
        "shoot_count", "max_session_per_year", "tier", "turnaround_weeks")
        VALUES ('{"amount": #{package.base_price.amount}, "currency": "#{Atom.to_string(package.base_price.currency)}"}',
        #{package.download_count}, #{package.full_time}, 'branding', #{package.min_years_experience}, #{package.shoot_count},
        #{package.max_session_per_year}, '#{package.tier}', #{package.turnaround_weeks});
      """)
    end)
  end

  def down do
    execute("""
    delete from package_base_prices where job_type in ('senior', 'pets', 'sports', 'cake_smash')
    """)

    execute("""
    delete from package_base_prices where job_type = 'birth'
    """)

    execute("""
    delete from package_base_prices where job_type = 'branding'
    """)
  end
end
