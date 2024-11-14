defmodule TodoplaceWeb.Live.Admin.AutomationsReportIndex do
  @moduledoc "update admin global settings"
  use TodoplaceWeb, live_view: [layout: false]

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> ok()
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :class, "border flex items-center justify-center rounded-lg p-8")

    ~H"""
    <header class="p-8 bg-gray-100">
      <h1 class="text-4xl font-bold">Automation Reports</h1>
    </header>
    <nav class="p-8">
      <ul class="mt-4 font-bold grid gap-10 grid-cols-1 sm:grid-cols-4 text-blue-planning-300">
        <li><.link navigate={~p"/admin/automations/sent-today-report"} class={@class}>Today Report</.link></li>
        <li class={"#{@class} opacity-50"}>Prediction report (coming soon)</li>
      </ul>
    </nav>
    """
  end
end
