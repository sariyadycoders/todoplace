defmodule TodoplaceWeb.OrganizationLive.AddOrganizationComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Todoplace.{Profiles, Organization, Workers.CleanStore}
  @impl true
  def update(assigns, socket) do
    organizations =
      case assigns.user_data.user_organizations_ids do
        nil -> []
        ids -> Todoplace.Cache.get_organizations(ids)
      end

    socket
    |> assign(assigns)
    |> assign(organizations: organizations)
    |> assign(user_id: assigns.user_data.current_user.id)
    |> ok()
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    organization_id = String.to_integer(id)

    case Todoplace.Organization.toggle_status(organization_id) do
      :ok ->
        send(socket.parent_pid, {:update_status, organization_id})

        socket
        |> put_flash(:info, "Organization status updated successfully")
        |> noreply()

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to update organization status")
        |> noreply()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col modal p-30">
      <div class="flex items-start justify-between flex-shrink-0">
        <h1 class="mb-4 text-3xl font-bold">
          Add Organization
        </h1>

        <button
          phx-click="modal"
          phx-value-action="close"
          title="close modal"
          type="button"
          class="p-2"
        >
          <.icon name="close-x" class="w-3 h-3 stroke-current stroke-2 sm:stroke-1 sm:w-6 sm:h-6" />
        </button>
      </div>
      <%= for organization <- @organizations do %>
        <div class="grid sm:grid-cols-3 gap-2 border p-3 items-center sm:pt-0 sm:px-0 sm:pb-2 sm:border-b sm:border-t-0 sm:border-x-0 rounded-lg sm:rounded-none border-gray-100 mt-2">
          <div class="flex flex-col">
            <p><%= Map.get(organization, :name, "") %></p>
          </div>
          <hr class="sm:hidden border-gray-100 my-2" />
          <div class="sm:col-span-1 grid sm:flex gap-2 sm:gap-0 overflow-hidden">
            <p>
              <%= Map.get(organization, :slug, "") %>
            </p>
          </div>
          <hr class="sm:hidden border-gray-100 my-2" />
          <div class="sm:col-span-1 grid sm:flex gap-2 sm:gap-0 overflow-hidden slider-container">
            <p
              phx-click="remove-from-selected-list"
              phx-value-id={Map.get(organization, :id, 0)}
              phx-value-value={Map.get(organization, :id, "")}
              class="cursor-pointer"
            >
              <%= if Todoplace.Organization.get_org_status(@user_id, Map.get(organization, :id, 0)) == :active do %>
                Active
              <% else %>
                Inactive
              <% end %>
            </p>
          </div>
          <hr class="sm:hidden border-gray-100 my-2" />
        </div>
      <% end %>
      <div>
        <div class="flex flex-col py-6 bg-white gap-2 sm:flex-row-reverse">
          <button class="px-8 btn-primary" title="Save" phx-target={@myself}>
            Save
          </button>
          <button
            class="btn-secondary"
            title="cancel"
            type="button"
            phx-click="modal"
            phx-value-action="close"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
    """
  end
end
