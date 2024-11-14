defmodule TodoplaceWeb.Live.Profile.Settings do
  @moduledoc false
  use TodoplaceWeb, :live_view
  import TodoplaceWeb.Live.User.Settings, only: [settings_nav: 1, card: 1]
  alias Todoplace.{Repo, Profiles}

  @impl true
  def mount(_params, _session, %{assigns: %{current_user: user}} = socket) do
    %{organization: organization} = Repo.preload(user, :organization)
    url = Profiles.public_url(organization)
    embed_code = Profiles.embed_code(organization)

    socket
    |> assign(:page_title, "Settings")
    |> assign(profile_url: url, organization: organization, embed_code: embed_code)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_nav socket={@socket} live_action={@live_action} current_user={@current_user} intro_id="intro_settings_public_profile">
      <div class="flex flex-col justify-between flex-1 mt-5 flex-grow-0 sm:flex-row" id="intercom" phx-hook="IntercomPush">
        <div>
          <h1 class="text-2xl font-bold" {testid("settings-heading")}>Public Profile</h1>

          <p class="max-w-2xl my-2 text-base-250">
            Allow potential clients to contact you directly through a website that we host for you. Customize the type of photography you offer, color, cover photo, etc.
          </p>
        </div>
        <div class="text-center md:flex items-center gap-0 content-start">
          <div class="flex flex-shrink-0">
            <a href={~p"/package_templates?#{%{edit_photography_types: true}}"} class="text-right text-blue-planning-300 underline font-normal text-lg pt-0">Edit photography types</a>
          </div>
          <div class="fixed top-12 left-0 right-0 z-20 flex flex-shrink-0 w-full p-6 mt-1 bg-white sm:mt-0 sm:bottom-auto sm:static sm:items-start sm:w-auto">
            <button type="button" phx-click="edit-profile" class="w-full px-8 text-center btn-primary ">Customize Profile</button>
          </div>
        </div>
      </div>

      <hr class="my-4 sm:my-10" />

      <div class="mx-0 mt-2 sm:mt-4 pb-32 sm:pb-0 grid grid-cols-1 lg:grid-cols-2 gap-x-9 gap-y-6">
        <.card title="Share your profile">
          <div class={"flex flex-col #{unless Profiles.enabled?(@organization), do: "text-base-250" }"}>
            <div class={"font-bold rounded-lg border border-base-200 py-2 #{if Profiles.enabled?(@organization), do: "select-all", else: "select-none"}"}>
              <%= @profile_url %>
            </div>
            <button disabled={!Profiles.enabled?(@organization)} type="button" class={"self-auto w-auto py-3 mt-4 text-lg font-semibold border disabled:border-base-200 rounded-lg sm:self-end border-base-300 sm:w-36"} id="copy-public-profile-link" data-clipboard-text={@profile_url} phx-hook="Clipboard" data-intercom-event="Shared Public Profile">
                <div class="hidden p-1 mt-1 text-sm rounded shadow bg-base-100" role="tooltip">Copied!</div>

                Copy Link
            </button>
          </div>
        </.card>

        <.card title="Embed your lead form" class="intro-lead-form">
          <p class="mt-4 text-base-250">Have your own website? No worries, we have a form for you to embed on your site. </p>
            <button button type="button" class="self-auto w-auto py-3 mt-4 text-lg font-semibold border disabled:border-base-200 rounded-lg sm:self-end border-base-300 sm:w-36" phx-click="open-embed">
              Preview form
            </button>
        </.card>

        <.card title="Enable/disable your public profile">
          <p class="mt-4 text-base-250">Hide your public profile or make it visible.</p>

          <.form :let={_} for={%{}} as={:toggle} phx-change="toggle">
            <label class="mt-4 text-2xl flex">
              <input type="checkbox" class="peer hidden" checked={Profiles.enabled?(@organization)} />

              <div class="hidden peer-checked:flex">
                <div class="rounded-full bg-blue-planning-300 border border-base-100 w-16 p-1 flex justify-end mr-4">
                  <div class="rounded-full h-7 w-7 bg-base-100"></div>
                </div>
                Enabled
              </div>

              <div class="flex peer-checked:hidden">
                <div class="rounded-full w-16 p-1 flex mr-4 border border-blue-planning-300">
                  <div class="rounded-full h-7 w-7 bg-blue-planning-300"></div>
                </div>
                Disabled
              </div>
            </label>
          </.form>
        </.card>
      </div>
    </.settings_nav>
    """
  end

  @impl true
  def handle_event(
        "open-embed",
        _,
        socket
      ) do
    assigns = %{
      embed_code: socket.assigns.embed_code
    }

    socket
    |> push_event("intercom", %{event: "View Embed"})
    |> open_modal(TodoplaceWeb.Live.Profile.CopyContactFormComponent, assigns)
    |> noreply()
  end

  @impl true
  def handle_event("toggle", %{}, %{assigns: %{organization: organization}} = socket) do
    socket |> assign(organization: Profiles.toggle(organization)) |> noreply()
  end

  @impl true
  def handle_event("edit-profile", %{}, socket) do
    socket
    |> push_redirect(to: ~p"/profile/settings/edit")
    |> noreply()
  end

  @impl true
  def handle_event("intro_js" = event, params, socket),
    do: TodoplaceWeb.LiveHelpers.handle_event(event, params, socket)
end
