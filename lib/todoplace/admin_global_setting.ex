defmodule Todoplace.AdminGlobalSetting do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "admin_global_settings" do
    field(:title, :string)
    field(:description, :string)
    field(:slug, :string)
    field(:value, :string)
    field(:status, Ecto.Enum, values: [:active, :disabled, :archived])

    timestamps(type: :utc_datetime)
  end

  def changeset(%__MODULE__{} = admin_global_setting, attrs \\ %{}) do
    admin_global_setting
    |> cast(attrs, [
      :title,
      :slug,
      :description,
      :value,
      :status
    ])
    |> validate_required([:title, :slug, :status, :value])
  end
end
