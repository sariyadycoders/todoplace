defmodule TodoplaceWeb.InviteLive.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="px-6 py-10 text-4xl font-bold center-container">Invite users</h1>
      <div class="fixed top-12 left-0 right-0 z-20 flex flex-shrink-0 w-full p-6 mt-1 bg-white sm:mt-0 sm:bottom-auto sm:static sm:items-start sm:w-auto">
        <button type="button" phx-click="add-user" class="w-full px-8 text-center btn-primary">
          Add User
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("add-user", %{}, %{assigns: %{current_user: current_user}} = socket) do
    socket
    |> open_modal(TodoplaceWeb.InviteLive.AddMemberForm, %{
      organization_id: current_user.organization_id
    })
    |> noreply()
  end
end
