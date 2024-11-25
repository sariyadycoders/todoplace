defmodule TodoplaceWeb.Live.OrganizationLayoutHelpers do
  use TodoplaceWeb, :live_view

  defmacro __using__(_opts) do
    quote do
      @impl true
      def mount(params, session, socket) do
        {:ok, socket} = unquote(__MODULE__).mount(params, session, socket)
        {:ok, socket}
      end

      @impl true
      def handle_event("change_organization", %{"id" => id}, socket) do
        {:noreply, unquote(__MODULE__).handle_change_organization(id, socket)}
      end
    end
  end

  def mount(_params, _session, %{assigns: %{current_user: current_user}} = socket) do
    organizations = Todoplace.Accounts.user_active_organization(current_user.id, "Joined")
    organization = Enum.find(organizations, &(&1.id == current_user.organization_id))

    {:ok,
     socket
     |> assign(:organizations, organizations)
     |> assign(:current_organization, organization)}
  end

  def handle_change_organization(
        organization_id,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    Todoplace.Accounts.update_user(current_user.id, %{"organization_id" => organization_id})

    # TODO: Hurry
    organizations = Todoplace.Accounts.user_active_organization(current_user.id, "Joined")
    organization = Enum.find(organizations, &(&1.id == String.to_integer(organization_id)))

    assign(socket, current_organization: organization)
  end
end
