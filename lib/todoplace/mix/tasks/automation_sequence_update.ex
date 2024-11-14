defmodule Mix.Tasks.AutomationSequenceUpdate do
  @moduledoc false
  use Mix.Task
  alias Todoplace.{EmailAutomations, Subscriptions}

  def run(_) do
    load_app()

    update_automation_sequence()
  end

  defp update_automation_sequence() do
    get_all_organizations()
    |> Enum.each(fn organization ->
      status = if organization.enabled?, do: "enabled", else: "disabled"
      EmailAutomations.update_globally_automations_emails(organization.id, status)
    end)
  end

  ## Fetches the organizations in which subscription has been set :active
  defp get_all_organizations() do
    Subscriptions.organizations_with_active_subscription()
    |> Enum.map(&%{id: &1.id, enabled?: &1.global_automation_enabled})
  end

  defp load_app do
    if System.get_env("MIX_ENV") != "prod" do
      Mix.Task.run("app.start")
    end
  end
end
