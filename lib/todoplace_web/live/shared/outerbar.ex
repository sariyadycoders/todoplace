defmodule TodoplaceWeb.Shared.Outerbar do
  @moduledoc """
    Live component for sidebar
  """
import Ecto.Query, only: [from: 2]

  alias Todoplace.{
    Accounts,
    Accounts.User,
    Repo,
    UserOrganization
  }
  alias Phoenix.LiveView.JS
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.LiveHelpers

  @impl true
  def update(
        %{
          current_user_data: %{
            current_user: user,
            user_organizations_ids: ids,
            user_preferences: user_preferences,
            notification_counts: notification_counts
          },
          current_path: current_path,
        } = assigns,
        socket
      ) do
    user_organization_list = Todoplace.Cache.get_organizations(ids)
    sorted_organizations =
      user_organization_list
      |> Enum.sort_by(& &1.name)
      |> Enum.sort_by(&(&1.id == user.organization_id), :desc)

    socket
    |> assign(
      Enum.into(assigns, %{
        is_drawer_open?: is_drawer_open?(assigns),
        is_mobile_drawer_open?: false,
        firstlayer?: Map.get(user_preferences, "menu_collapsed", true),
        tour_id: "current_user",
        inner_id: "initials-menu-inner-content"
      })
    )
    |> assign(:user_organizations, sorted_organizations)
    |> assign(:current_organization_id, user.organization_id)
    |> assign(:current_path, current_path)
    |> assign(:notification_counts, notification_counts)
    |> ok()
  end

  @impl true
  def update(%{notification_count: _notification_counts}, socket) do
    # Update the component's state with the new data
    %{
      current_user: user,
      user_organizations_ids: ids,
      notification_counts: notification_counts,
    } =
    Todoplace.Cache.refresh_current_user_cache(socket.assigns.current_user_data.session_token)

    user_organization_list = Todoplace.Cache.get_organizations(ids)
    sorted_organizations =
      user_organization_list
      |> Enum.sort_by(& &1.name)
      |> Enum.sort_by(&(&1.id == user.organization_id), :desc)


    socket
    |> assign(:notification_counts, notification_counts)
    |> assign(:user_organizations, sorted_organizations)
    |> ok()

  end

  def update(assigns, socket) do
    socket
    |> assign(:is_drawer_open?, is_drawer_open?(assigns))
    |> ok()
  end



  @impl true
  def handle_event(
        "change_organization",
        %{"id" => id},
      %{assigns: %{current_user: current_user, current_path: current_path}} = socket
      ) do
    organization_id = String.to_integer(id)
    update_last_visited_page(current_user.id, current_user.organization.id, current_path)

    {:ok, user} =
      Accounts.update_user(current_user.id, %{"organization_id" => organization_id})

    Todoplace.Cache.refresh_current_user_cache(socket.assigns.current_user_data.session_token)
    user_organization =
      Repo.get_by!(UserOrganization, user_id: current_user.id, organization_id: organization_id)

    # Redirect or load the last visited page
    last_visited_page = user_organization.last_visited_page || "/home"

    socket
    |> push_redirect(to: last_visited_page, replace: true)
    |> noreply()
  end

  defp update_last_visited_page(user_id, organization_id, page) do

    {count, _} =
      Repo.update_all(
        from(u in UserOrganization,
          where: u.user_id == ^user_id and u.organization_id == ^organization_id
        ),
        set: [last_visited_page: page]
      )

    if count > 0 do
      {:ok, count}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def handle_event("collapse_first_layer", _, socket) do
    User.update_menu_collapsed(socket.assigns.current_user_data.current_user.id, !socket.assigns.firstlayer?)
    Todoplace.Cache.refresh_current_user_cache(socket.assigns.current_user_data.session_token)

    send_update(TodoplaceWeb.Shared.Sidebar, id: "application-sidebar", firstlayer?: !socket.assigns.firstlayer?)

    socket
    |> push_event("sidebar:collapse", %{
      is_drawer_open: socket.assigns.is_drawer_open?,
      is_firstlayer: !socket.assigns.firstlayer?
    })
    |> assign(firstlayer?: !socket.assigns.firstlayer?)
    |> noreply()
  end

  @impl true
  def handle_event("redirect_to_home", _, socket) do
    socket
    |> push_redirect(to: ~p"/home", replace: true)
    |> noreply()
  end

  def get_organization_notification_count(notification_counts, organization_id) do
    case Enum.find(notification_counts, fn {org_id, _count} -> org_id == organization_id end) do
      {^organization_id, count} -> count
      nil -> 0
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="sidebar-wrapper-two"
      phx-hook="CollapseSidebar"
      class="z-40"
      data-target={@myself}
    >
    
      <div class="h-12 bg-gray-800 flex items-center justify-between fixed left-0 right-0 top-0">
        <div class="flex gap-3 w-1/4 items-center text-white">
        </div>
        <div class="flex gap-3 w-1/4 items-center text-white relative">
          <div class="w-5/6">
            <.form :let={f} for={} as={:form} class="w-full">
              <.input field={f[:search]} type="mattermost-search" placeholder="Search" />
            </.form>
          </div>
          <div
            phx-click={JS.toggle(to: "#help-popup")}
            phx-click-away={JS.set_attribute({"style", "top: 110%; right: 10%; display: none"}, to: "#help-popup")}
            class="cursor-pointer"
          >
            <.icon name="question-mark" class="w-5 h-5 text-white fill-white" />
          </div>
          <div id="help-popup" style="top: 110%; right: 10%; display: none;" class="hidden absolute hidden bg-white border rounded-lg shadow-lg z-50 border-2 border-gray-300 w-60 flex flex-col">
            <div class="text-black border-b py-2 px-3 hover:bg-blue-planning-100 cursor-pointer hover:font-bold">
              User Guide
            </div>
            <div class="text-black border-b py-2 px-3 hover:bg-blue-planning-100 cursor-pointer hover:font-bold">
              Keyboard Shortcuts
            </div>
            <div class="text-black py-2 px-3 hover:bg-blue-planning-100 cursor-pointer hover:font-bold">
              Give Feedback
            </div>
          </div>

        </div>

        <.live_component module={TodoplaceWeb.UserControlsComponent} id={assigns[:id] || "default-topbar"} current_user_data={@current_user_data} />
      </div>

      <div class="flex gap-3 items-center fixed top-2 left-4 z-50">
        <div class="">
          <div
            class="rounded-lg h-8 w-8 flex items-center justify-center text-lg cursor-pointer relative"
            phx-click={JS.toggle(to: "#popover-content-menu")}
            phx-click-away={JS.set_attribute({"style", "top: 110%; display: none"}, to: "#popover-content-menu")}
          >
            <.icon name="hamburger" class="w-5 h-5 text-white fill-white" />
            <div id="popover-content-menu" style="top: 110%; display: none;" class="hidden absolute left-0 hidden bg-white border rounded-lg shadow-lg z-50 border-2 border-gray-300 w-72">
              <%= for app <- Todoplace.Cache.get_all_apps do %>
                <.app_item
                  app={app}
                  target={@myself}
                />
              <% end %>
            </div>
          </div>
        </div>

        <div class="hover:bg-gray-600 p-2 rounded-lg">
          <div
            class={["text-white cursor-pointer", if(@firstlayer?, do: "flip-icon")]}
            phx-click="collapse_first_layer"
            phx-target={@myself}
          >
            <.icon name="collapse" class="w-4 h-4" />
          </div>
        </div>

        <%= unless @firstlayer? do %>
          <div class="">
            <div
              class="bg-white rounded-lg h-8 w-8 flex items-center justify-center text-lg cursor-pointer relative"
              phx-click={JS.toggle(to: "#popover-content-first-org")}
              phx-click-away={JS.set_attribute({"style", "top: 110%; display: none"}, to: "#popover-content-first-org")}
            >
              <.organization_logo organization={
                Enum.find(@user_organizations, fn org -> org.id == @current_organization_id end)
              } />
              <div id="popover-content-first-org" style="top: 110%; display: none;" class="hidden absolute left-0 hidden bg-white border rounded-lg shadow-lg z-50 border-2 border-gray-300 w-72">
                <%= for organization <- @user_organizations do %>
                  <.action_item
                    organization={organization}
                    current_organization_id={@current_organization_id}
                    target={@myself}
                    notification_counts={@notification_counts}
                  />
                <% end %>
                <.add_orgniation {assigns} />
              </div>
            </div>
          </div>
        <% end %>

        <div class={["bg-white rounded-md px-2 pt-1 font-bold"]}>
          <%=@current_user.organization.name%>
        </div>
      </div>
      <div class="sm:hidden bg-white p-2 flex items-center justify-between fixed top-0 left-0 right-0 w-full">
        <button
          phx-click="open"
          phx-target={@myself}
          data-drawer-type="mobile"
          data-drawer-target="default-sidebar"
          data-drawer-toggle="default-sidebar"
          aria-controls="default-sidebar"
          type="button"
          class="inline-flex items-center p-2 mt-2 ms-3 text-sm text-gray-500 rounded-lg hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-gray-200 "
        >
          <span class="sr-only">Open sidebar</span>
          <.icon name="hamburger" class="h-4 text-base-300 w-9" />
        </button>
        <.link navigate={if @current_user, do: ~p"/home", else: ~p"/"} title="Todoplace">
          <.icon name="logo" class="my-4 w-28 h-9 mr-6" />
        </.link>
        <.initials_menu {assigns} />
      </div>
      <div id="custom-context-menu" class="hidden custom-menu">
        <ul>
          <li phx-click="remove-from-selected-list" phx-value-id="">Remove</li>
        </ul>
      </div>
      <div id="org-context-add-menu" class="hidden custom-menu">
        <ul>
          <li phx-click="add-organization" phx-value-id="">Add Organization</li>
          <li phx-click="create-organization" phx-value-id="">Create Organization</li>
        </ul>
      </div>

      <div
        class={
          classes(
            "fixed top-0 bottom-0 z-40 w-16 bg-gray-800 gap-5 items-center top-12 pt-2 text-black transition-all",
            %{
              "flex flex-col left-0" => @firstlayer?,
              "mome" => @firstlayer?,
              "-left-16" => !@firstlayer?
            }
          )
        }
        id="first-layer"
      >
        <div class="flex flex-col gap-5 items-center justify-center">
        <%= for organization <- @user_organizations do %>
          <div
            class="bg-white rounded-lg h-12 w-12 flex items-center justify-center text-lg cursor-pointer relative"
            phx-click={if organization.id != @current_organization_id, do: "change_organization"}
            phx-value-id={organization.id}
            id={"selected-org-#{Map.get(organization, :id, "")}"}
            phx-target={@myself}
            phx-hook="PreventContextMenu"
            data-org-id={organization.id}
          >
              <div class="w-5 h-5 bg-green-200 absolute -top-1 -right-1 text-sm rounded-full flex items-center justify-center">
                <%= get_organization_notification_count(@notification_counts, organization.id) %>
              </div>

            <.organization_logo organization={organization} />
          </div>
        <% end %>
        </div>
        <div
          class="bg-white rounded-lg h-12 w-12 flex items-center justify-center text-lg cursor-pointer mb-5"
          id="nav-organization-menu"
          phx-hook="AddOrganizationMenu"
        >
          <h1 class="text-xl font-bold">+</h1>
        </div>
      </div>
    </div>
    """
  end

  def initials_menu(assigns) do
    ~H"""
    <div
      id="initials-menu"
      class="relative flex flex-row justify-end cursor-pointer"
      phx-hook="ToggleContent"
    >
      <%= if @current_user do %>
        <div
          id={@inner_id}
          class="absolute top-0 right-0 flex flex-col items-end hidden cursor-default text-base-300 toggle-content"
        >
          <div class="p-4 -mb-2 bg-white shadow-md cursor-pointer text-base-300">
            <.icon name="close-x" class="w-4 h-4 stroke-current stroke-2" />
          </div>
          <div class="bg-gray-100 rounded-lg shadow-md w-max z-30">
            <.link
              navigate={~p"/users/setting"}
              title="Account"
              class="flex items-center px-2 py-2 bg-white"
            >
              <.initials_circle user={@current_user} />
              <div class="ml-2 font-bold">Account</div>
            </.link>

            <%= if Enum.any?(@current_user.onboarding.intro_states) do %>
              <.live_component
                module={TodoplaceWeb.Live.RestartTourComponent}
                id={@tour_id}
                ,
                current_user={@current_user}
              />
            <% end %>
            <.form :let={_} for={%{}} as={:sign_out} action={~p"/users/log_out"} method="delete">
              <%= submit("Logout", class: "text-center py-2 w-full") %>
            </.form>
          </div>
        </div>
        <div
          class="flex flex-col items-center justify-center text-sm text-base-300 bg-gray-100 rounded-full w-9 h-9 pb-0.5"
          title={@current_user.name}
        >
          <%= User.initials(@current_user) %>
        </div>
      <% end %>
    </div>
    """
  end

  defp is_drawer_open?(%{current_user: %{onboarding: onboarding}}) do
    Map.get(onboarding, :sidebar_open_preference, true)
  end

  defp is_drawer_open?(_) do
    true
  end

  def outer_header(assigns) do
    ~H"""
    <.live_component module={__MODULE__} id={assigns[:id] || "app-org-sidebar"} {assigns} />
    """
  end

  def organization_logo(assigns) do
    ~H"""
    <%= case Todoplace.Profiles.logo_url(@organization) do %>
      <% nil -> %>
        <h1 class="text-xl font-bold"><%= String.trim(@organization.name) |> String.first() |> String.upcase() %></h1>
      <% url -> %>
        <img class="rounded-lg h-8 w-8" src={url} />
    <% end %>
    """
  end

  def action_item(assigns) do
    assigns =
      Enum.into(assigns, %{
        url: Todoplace.Profiles.logo_url(assigns.organization)
      })

    ~H"""
    <div
      class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold"
      phx-click={if @organization.id != @current_organization_id, do: "change_organization"}
      phx-value-id={@organization.id}
      phx-target={@target}
    >
      <%= if @url do %>
        <img class="inline-block w-9 h-9 mr-4 rounded-lg border border-black text-blue-planning-300" src={@url} />
      <% else %>
        <div class="rounded-lg w-9 h-9 border border-black text-blue-planning-300 mr-4 flex items-center justify-center">
          <h1 class="">
            <%= String.trim(@organization.name) |> String.first() |> String.upcase() %>
          </h1>
        </div>
      <% end %>
      <%= @organization.name %>
      <div class="w-5 h-5 bg-green-200 absolute -top-1 -right-1 text-sm rounded-full flex items-center justify-center">
          <%= get_organization_notification_count(@notification_counts, @organization.id) %>
      </div>
    </div>
    """
  end

  def app_item(assigns) do
    assigns =
      Enum.into(assigns, %{
        url: nil
      })

    ~H"""
    <div
      class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold"
    >
      <%= if @url do %>
        <img class="inline-block w-9 h-9 mr-4 rounded-lg border border-black text-blue-planning-300" src={@url} />
      <% else %>
        <div class="rounded-lg w-9 h-9 border border-black text-blue-planning-300 mr-4 flex items-center justify-center">
          <h1 class="">
            <%= String.trim(@app.id) |> String.first() |> String.upcase() %>
          </h1>
        </div>
      <% end %>
      <%= @app.id %>
    </div>
    """
  end

  def add_orgniation(assigns) do
    ~H"""
    <div
      class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold"
      phx-click="add-organization"
    >
        <div class="rounded-lg w-9 h-9 mr-4 border border-black text-blue-planning-300 flex items-center justify-center">
        </div>
      <%= "Add organization" %>
    </div>
    <div
      class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold"
      phx-click="create-organization"
    >
        <div class="rounded-lg w-9 h-9 mr-4 border border-black text-blue-planning-300 flex items-center justify-center">
          <h1 class="">
            <%= "+" %>
          </h1>
        </div>
      <%= "Create organization" %>
    </div>

    """
  end
end
