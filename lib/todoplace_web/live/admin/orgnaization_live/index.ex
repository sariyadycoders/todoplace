defmodule TodoplaceWeb.OrganizationLive.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view
  alias Todoplace.Organization

  def mount(_params, _session, %{assigns: %{current_user_data: user_data}} = socket) do
    Organization.list_organizations(user_data.current_user.id)

    # if connected?(socket), do: Phoenix.PubSub.subscribe(Todoplace.PubSub, "organization:#{user_data.current_user.id}")

    organizations =
      user_data.user_all_organizations_ids
      |> Todoplace.Cache.get_organizations()

    {:ok, assign(socket, organizations: organizations, success_message: nil)}
  end

  # def handle_info({:update_organization_list, notification_count}, socket) do

  #   # Update the organizations in the socket assign
  #    send_update(TodoplaceWeb.Shared.Outerbar, id: "app-org-sidebar", notification_count: notification_count)
  #   {:noreply, assign(socket, :notification_count, notification_count)}
  # end

  @impl true
  def handle_event("add-user", %{"organization_id" => organization_id}, socket) do
    socket
    |> open_modal(TodoplaceWeb.InviteLive.AddMemberForm, %{
      organization_id: organization_id
    })
    |> noreply()
  end

  @impl true
  def handle_event("view-users", %{"organization_id" => organization_id}, socket) do
    socket
    |> push_redirect(to: ~p"/organizations/#{organization_id}")
    |> noreply()
  end

  @impl true
  def handle_event("add-organization", _, %{assigns: %{current_user_data: user_data}} = socket) do
    socket
    |> open_modal(TodoplaceWeb.OrganizationLive.AddOrganizationComponent, %{
      user_data: user_data
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "toggle",
        %{"toggle" => %{"organization_id" => organization_id}},
        %{assigns: %{current_user_data: user_data, organizations: organizations}} = socket
      ) do
    organization_id = String.to_integer(organization_id)

    organization = Enum.find(organizations, &(&1.id == organization_id))

    Todoplace.Accounts.toggle_organization_status(organization, !organization.is_active)
    |> case do
      {:ok, _} ->
        organizations =
          user_data.user_all_organizations_ids
          |> Todoplace.Cache.get_organizations()

        if Enum.any?(organizations, & &1.is_active) do
          socket
          |> assign(organizations: organizations)
          |> put_flash(:success, "Organization is updated")
        else
          socket
          |> put_flash(:success, "All Organization is deactivated")
          |> push_redirect(to: ~p"/create_organization")
        end

      _ ->
        socket
        |> put_flash(:error, "Something went wrong")
    end
    |> noreply()
  end

  @impl true
  def handle_info(
        {:update, organization, flash_message},
        %{assigns: %{current_user_data: user_data}} = socket
      ) do
    socket
    |> update(:organizations, fn organizations -> [organization | organizations] end)
    # |> put_flash(:success, flash_message)
    |> noreply()
  end

  defp list_organizations(user_id) do
    Organization.list_organizations(user_id)
  end

  def actions(assigns) do
    ~H"""
    <div
      class="flex items-center md:ml-auto w-full md:w-auto left-3 sm:left-8"
      data-offset-x="-21"
      phx-update="ignore"
      data-placement="bottom-end"
      phx-hook="Select"
      id={"manage-client-#{Map.get(@organization, :id, "")}"}
    >
      <button
        {testid("actions")}
        title="Manage"
        class="btn-tertiary px-2 py-1 flex items-center gap-3 mr-6 text-blue-planning-300 xl:w-auto w-full"
      >
        Actions
        <.icon
          name="down"
          class="w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 open-icon"
        />
        <.icon
          name="up"
          class="hidden w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 close-icon"
        />
      </button>

      <div class="z-10 flex flex-col hidden w-44 bg-white border rounded-lg shadow-lg popover-content">
        <%= for %{title: title, action: action, icon: icon} <- actions() do %>
          <button
            title={title}
            type="button"
            phx-click={action}
            phx-value-organization_id={Map.get(@organization, :id, "")}
            class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold"
          >
            <.icon
              name={icon}
              class={
                classes("inline-block w-4 h-4 mr-3 fill-current", %{
                  "text-red-sales-300" => icon == "trash",
                  "text-blue-planning-300" => icon != "trash"
                })
              }
            />
            <%= title %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp actions do
    [
      %{title: "Invite user", action: "add-user", icon: "three-people"},
      %{title: "View Users", action: "view-users", icon: "eye"}
    ]
  end
end
