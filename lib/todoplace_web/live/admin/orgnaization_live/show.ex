defmodule TodoplaceWeb.OrganizationLive.Show do
  @moduledoc false
  use TodoplaceWeb, :live_view
  alias Todoplace.{Organization, Accounts}

  def mount(_params, _session, %{assigns: %{current_user_data: user_data}} = socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => organization_id}, _session, socket) do
    organization = Todoplace.Cache.get_organization_data(organization_id)
    users = Enum.map(organization.organization_users, & &1.user)

    socket
    |> assign(organization: organization, users: users)
    |> noreply()
  end

  @impl true
  def handle_event("remove-user", %{"user_id" => user_id}, socket) do
    organization_id = socket.assigns.organization.id

    user =
      socket.assigns.users
      |> Enum.find(&(&1.id == String.to_integer(user_id)))

    case Accounts.remove_user(user, organization_id) do
      {:ok, _} ->
        organization = Todoplace.Cache.get_organization_data(organization_id)
        users = Enum.map(organization.organization_users, & &1.user)

        socket
        |> assign(organization: organization, users: users)
        |> put_flash(:success, "user is removed")

      _ ->
        socket
        |> put_flash(:error, "Something went wrong")
    end
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <header>
      <div class="center-container p-6 pt-10">
        <div class="flex content-center justify-between md:flex-row mt-6 sm:mt-0">
          <div class="flex-col">
            <h1 class="text-4xl font-bold center-container">
              Organization Users
            </h1>
          </div>
          <div class="fixed top-12 left-0 right-0 z-10 flex flex-shrink-0 w-full sm:p-0 p-6 mt-1 sm:mt-0 sm:bottom-auto sm:static sm:items-start sm:w-auto">
            <%!-- <a
             title="Add user"
             class="w-full md:w-auto btn-primary text-center hover:cursor-pointer"
             phx-click="add-organization"
           >

           </a> --%>
          </div>
        </div>
        <hr class="mt-4 sm:mt-10" />
      </div>
    </header>
    <div class="md:p-6 center-container">
      <div class="hidden items-center sm:grid sm:grid-cols-4 gap-2 border-b-8 border-blue-planning-300 font-semibold text-lg pb-6">
        <div>Name</div>
        <div class="sm:col-span-1">Email</div>
        <div>Status</div>
        <div></div>
      </div>
      <%= for organization_user <- @organization.organization_users do %>
        <div class="grid sm:grid-cols-4 gap-2 border p-3 items-center sm:pt-0 sm:px-0 sm:pb-2 sm:border-b sm:border-t-0 sm:border-x-0 rounded-lg sm:rounded-none border-gray-100 mt-2">
          <div class="flex flex-col">
            <p><%= organization_user.user.name %></p>
          </div>
          <hr class="sm:hidden border-gray-100 my-2" />
          <div class="sm:col-span-1 grid sm:flex gap-2 sm:gap-0 overflow-hidden">
            <p>
              <%= organization_user.user.email %>
            </p>
          </div>
          <div>
           <%= organization_user.status %>
          </div>
          <hr class="sm:hidden border-gray-100 my-2" />
           <.actions organization_user={organization_user} />
        </div>
      <% end %>
    </div>
    """
  end

  def actions(assigns) do
    ~H"""
    <div
      class="flex items-center md:ml-auto w-full md:w-auto left-3 sm:left-8"
      data-offset-x="-21"
      phx-update="ignore"
      data-placement="bottom-end"
      phx-hook="Select"
      id={"manage-client-#{Map.get(@organization_user.user, :id, "")}"}
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
            phx-click={@organization_user.status != "removed" && action}
            phx-value-user_id={@organization_user.user.id}
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
      %{title: "Remove user", action: "remove-user", icon: "trash"}
      # %{title: "View Users", action: "add-user", icon: "eye"}
    ]
  end
end
