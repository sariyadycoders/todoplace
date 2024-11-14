defmodule TodoplaceWeb.OrganizationLive do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "onboarding"]
  # import TodoplaceWeb.OrganizationLive.CreateOrganizationComponent

  alias Todoplace.{Accounts, Accounts.User, Cache, Profiles, Organization, Workers.CleanStore}

  @impl true
  def mount(_, session, socket) do
    socket
    |> assign(:organization, %Organization{})
    |> assign_changeset()
    |> assign(current_user_data: Cache.get_user_from_db(session["user_token"]))
    |> ok()
  end

  def handle_event(
        "validate",
        %{"organization" => params},
        %{assigns: %{organization: organization}} = socket
      ) do
    socket
    |> assign_changeset(:validate, params)
    |> noreply()
  end

  @impl true
  def handle_event(
        "submit",
        %{"organization" => %{"name" => name}},
        %{assigns: %{current_user_data: user_data}} = socket
      ) do
    %{current_user: current_user} = user_data

    Organization.create_organization(%{name: name}, current_user.id)
    |> case do
      {:ok, %{id: organization_id}} ->
        {:ok, _user} =
          Todoplace.Accounts.update_user(current_user.id, %{"organization_id" => organization_id})

        socket
        |> push_redirect(to: ~p"/home", replace: true)

      {:error, _} ->
        socket
        |> put_flash(:error, "Error while creating organization")
    end
    |> noreply()
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-start w-screen min-h-screen p-5 sm:justify-center bg-blue-planning-200">
      <div class="container px-6 pt-8 pb-6 bg-white rounded-lg shadow-md max-w-screen-sm sm:p-14">
        <h1 class="title">Create your Organization</h1>
        <.form :let={f} for={@changeset} phx-submit="submit" phx-change="validate">
          <%= labeled_input(f, :name,
            placeholder: "Organization Name",
            phx_debounce: "500",
            wrapper_class: "mb-4"
          ) %>
          <%= submit("Create ", disabled: !@changeset.valid?, class: "btn-primary") %>
        </.form>
      </div>
    </div>
    """
  end

  defp build_changeset(
         %{assigns: %{organization: organization}},
         params
       ) do
    Organization.name_changeset(organization, params)
  end

  defp assign_changeset(socket, action \\ nil, params \\ %{}) do
    changeset = build_changeset(socket, params) |> Map.put(:action, action)

    assign(socket, changeset: changeset)
  end
end
