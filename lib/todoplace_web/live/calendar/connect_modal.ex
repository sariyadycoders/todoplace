defmodule TodoplaceWeb.Live.Calendar.Shared.ConnectModal do
  @moduledoc false
  use TodoplaceWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:nylas_calendar_hint, to_form(%{"nylas_calendar_hint" => nil}))
    |> assign(:show_advanced, false)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dialog">
      <h1 class="flex justify-between mb-4 text-3xl font-bold">
        2-way Calendar Sync
        <button
          phx-click="modal"
          phx-value-action="close"
          title="close modal"
          type="button"
          class="p-2"
        >
          <.icon name="close-x" class="w-4 h-4 stroke-current stroke-2" />
        </button>
      </h1>
      <img src="/images/calendar-sync-smaller.jpg" />
      <p class="font-bold mt-4">Securely connect your external and Todoplace calendars so you can:</p>
      <ul class="list-disc ml-4">
        <li>
          Avoid schedule conflicts and double-bookings between your photography and personal calendars
        </li>
        <li>
          Have all your external calendar events and details sync with your Todoplace account and vice versa!
        </li>
      </ul>
      <button
        type="button"
        phx-click="show-advanced"
        phx-target={@myself}
        class="flex items-center gap-2 mt-2 justify-end"
      >
        <span class="link">Advanced Settings</span>
        <.icon
          name="down"
          class={classes("w-4 h-2 text-blue-planning-300", %{"rotate-180" => @show_advanced})}
        />
      </button>
      <div class={
        classes("border rounded-lg p-2 mt-2", %{"" => @show_advanced, "hidden" => !@show_advanced})
      }>
        <h3 class="font-bold">Change Calendar Provider</h3>
        <p class="text-base-250">
          If your calendar provider is different than your email domain/provider, select override here
        </p>
        <.form :let={f} for={@nylas_calendar_hint} phx-change="change-calendar" phx-target={@myself}>
          <%= select_field(
            f,
            :nylas_calendar_hint,
            [
              {"Apple (iCloud)", "icloud"},
              {"Google (gmail)", "gmail"},
              {"Microsoft (Outlook/Office 365)", "microsoft"},
              {"Exchange", "exchange"}
            ],
            prompt: "select one…",
            class: "select w-full focus:outline-none focus:border-base-300 px-3 mt-2"
          ) %>
        </.form>
      </div>
      <TodoplaceWeb.LiveModal.footer class="pt-8">
        <a class="btn-primary" id="button-connect" href={@nylas_url}>Sync Calendars</a>
        <button
          class="btn-secondary"
          title="cancel"
          type="button"
          phx-click="modal"
          phx-value-action="close"
        >
          Close
        </button>
      </TodoplaceWeb.LiveModal.footer>
    </div>
    """
  end

  def handle_event("change-calendar", %{"nylas_calendar_hint" => nylas_calendar_hint}, socket) do
    socket |> assign_nylas_url(nylas_calendar_hint) |> noreply()
  end

  @impl true
  def handle_event("show-advanced", _params, %{assigns: %{show_advanced: show_advanced}} = socket) do
    socket
    |> assign(:show_advanced, !show_advanced)
    |> noreply()
  end

  def open(%{assigns: _assigns} = socket, %{nylas_url: nylas_url} = _params) do
    socket |> open_modal(__MODULE__, %{nylas_url: nylas_url})
  end

  defp assign_nylas_url(%{assigns: %{nylas_url: nylas_url}} = socket, nylas_calendar_hint) do
    nylas_url = "#{nylas_url}&provider=#{nylas_calendar_hint}"

    socket |> assign(:nylas_url, nylas_url)
  end
end
