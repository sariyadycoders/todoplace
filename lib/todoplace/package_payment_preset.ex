defmodule Todoplace.PackagePaymentPreset do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias Todoplace.{Organization, PackagePaymentSchedule}

  schema "package_payment_presets" do
    field :schedule_type, :string
    field :job_type, :string
    field :fixed, :boolean

    belongs_to :organization, Organization
    has_many(:package_payment_schedules, PackagePaymentSchedule, where: [package_id: nil])

    timestamps()
  end

  def changeset(%__MODULE__{} = package_payment_preset, attrs) do
    package_payment_preset
    |> cast(attrs, [:job_type, :schedule_type, :fixed, :organization_id])
    |> validate_required([:job_type, :schedule_type, :fixed, :organization_id])
  end
end
