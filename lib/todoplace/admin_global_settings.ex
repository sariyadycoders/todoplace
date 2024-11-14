defmodule Todoplace.AdminGlobalSettings do
  @moduledoc "context module for admin global settings"

  import Ecto.Query, warn: false

  alias Todoplace.{Repo, AdminGlobalSetting}

  @doc """
  Gets admin global setting by slug.

  Returns nil if the admin global setting does not exist.
  """
  def get_settings_by_slug(slug) do
    Repo.get_by(AdminGlobalSetting, slug: slug)
  end

  @doc """
  Gets active admin global settings.

  Returns [] if the admin global settings does not exist.
  """
  def get_all_active_settings() do
    from(ags in AdminGlobalSetting, where: ags.status == :active, order_by: ags.id)
    |> Repo.all()
  end

  @doc """
  Gets all admin global settings.

  Returns [] if the admin global settings does not exist.
  """
  def get_all_settings() do
    from(ags in AdminGlobalSetting, order_by: ags.id)
    |> Repo.all()
  end

  def update_setting!(%AdminGlobalSetting{} = admin_global_setting, attrs) do
    admin_global_setting
    |> AdminGlobalSetting.changeset(attrs)
    |> Repo.update!()
  end

  def delete_setting(setting), do: setting |> Repo.delete()
end
