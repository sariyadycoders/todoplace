defmodule Todoplace.Apps do
  import Ecto.Query
  alias Todoplace.Repo
  alias Todoplace.App

  # Fetch all apps from the database
  def get_all_apps do
    Repo.all(App)
  end

  # Fetch an app by ID
  def get_app_by_id(app_id) do
    Repo.get(App, app_id)
  end
end
