defmodule TodoplaceWeb.Shared.Sidebar do
  @moduledoc """
    Live component for sidebar
  """

  alias Todoplace.{
    Accounts.User,
    Repo
  }

  alias Phoenix.LiveView.JS

  use TodoplaceWeb, :live_component

  import TodoplaceWeb.LiveHelpers
  import Todoplace.Onboardings, only: [user_update_sidebar_preference_changeset: 2]
  import Todoplace.Onboardings.Welcome, only: [get_percentage_completed_count: 1]

  @impl true
  def update(
        %{
          current_user_data: %{
            current_user: user,
            user_organizations_ids: ids,
            user_preferences: user_preferences
          }
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
    |> assign(:onboarding_percentage, get_percentage(assigns))
    |> assign(:user_organizations, sorted_organizations)
    |> assign(:current_organization_id, user.organization_id)
    |> assign(:notification_count, 0)
    |> ok()
  end

  def update(assigns, socket) do
    socket
    |> assign(firstlayer?: assigns.firstlayer?)
    |> ok()
  end

  def handle_info({:collaps_layer, value}, socket) do
    socket
    |> assign(firstlayer?: value)
    |> noreply()
  end

  @impl true
  def handle_event(
        "collapse",
        _unsigned_params,
        %{
          assigns: %{
            is_drawer_open?: is_drawer_open?,
            current_user: current_user,
            firstlayer?: is_firstlayer
          }
        } = socket
      ) do
    current_user
    |> user_update_sidebar_preference_changeset(%{
      onboarding: %{sidebar_open_preference: !is_drawer_open?}
    })
    |> Repo.update!()

    send_update(TodoplaceWeb.Shared.Outerbar,
      id: "app-org-sidebar",
      is_drawer_open?: !is_drawer_open?
    )

    socket
    |> push_event("sidebar:collapse", %{
      is_drawer_open: !is_drawer_open?,
      is_firstlayer: is_firstlayer
    })
    |> assign(:is_drawer_open?, !is_drawer_open?)
    |> noreply()
  end

  @impl true
  def handle_event(
        "open",
        _unsigned_params,
        %{assigns: %{is_mobile_drawer_open?: is_mobile_drawer_open?}} = socket
      ) do
    socket
    |> push_event("sidebar:mobile", %{
      is_mobile_drawer_open?: !is_mobile_drawer_open?
    })
    |> assign(:is_mobile_drawer_open?, !is_mobile_drawer_open?)
    |> noreply()
  end

  @impl true
  def handle_event(
        "change_organization",
        %{"id" => id},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    organization_id = String.to_integer(id)

    {:ok, user} =
      Todoplace.Accounts.update_user(current_user.id, %{"organization_id" => organization_id})

    Todoplace.Cache.refresh_current_user_cache(socket.assigns.current_user_data.session_token)

    socket
    |> push_redirect(to: ~p"/home", replace: true)
    # |> assign(:current_organization_id, organization_id)
    |> noreply()
  end

  @impl true
  def handle_event("collapse_first_layer", _, socket) do
    socket
    |> assign(firstlayer?: !socket.assigns.firstlayer?)
    |> noreply()
  end

  @impl true
  def handle_event("redirect_to_home", _, socket) do
    socket
    |> push_redirect(to: ~p"/home", replace: true)
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="sidebar-wrapper"
      phx-hook="CollapseSidebar"
      data-drawer-open={"#{@is_drawer_open?}"}
      data-mobile-drawer-open={"#{@is_mobile_drawer_open?}"}
      class="z-30"
      data-target={@myself}
    >
      <aside
        id="default-sidebar"
        class={
          classes(
            "fixed top-0 bottom-0 overflow-y-scroll z-20 max-h-screen h-full transition-all",
            %{"left-16" => @firstlayer?, "left-0" => !@firstlayer?}
          )
        }
        aria-label="Sidebar"
      >
        <div class="h-full flex flex-col overflow-y-auto overflow-x-hidden bg-white border-r border-r-base-200 no-scrollbar">
          <div class="flex items-center justify-between px-4">
            <.link navigate={if @current_user, do: ~p"/home", else: ~p"/"} title="Todoplace">
              <.icon name="logo" class="my-4 w-28 h-9 mr-6 logo-full" />
              <.icon name="logo-badge" class="w-5 h-5 my-4 mr-6 logo-badge" />
            </.link>
            <.initials_menu
              {assigns}
              tour_id="current_user_sidebar"
              id="initials-menu-sidebar"
              inner_id="initials-menu-inner-content-sidebar"
            />
          </div>
          <nav class="flex flex-col divide-y relative">
            <.nav_link
              title="Dashboard"
              to={~p"/home"}
              socket={@socket}
              live_action={@live_action}
              current_user={@current_user}
              class="text-sm px-4 flex items-center py-2.5 whitespace-nowrap text-base-250 transition-all hover:bg-blue-planning-100"
              active_class="bg-blue-planning-100 text-black font-bold"
            >
              <div
                class="inline"
                phx-hook="Tooltip"
                data-hint="Dashboard"
                data-position="right"
                id="tippydashboard"
              >
                <.icon name="home" class="inline-block w-5 h-5 mr-2 text-black shrink-0" />
              </div>
              <span>Dashboard</span>
            </.nav_link>
            <%= for {%{heading: heading, is_default_opened?: is_default_opened?, items: items}, primary_index} <- Enum.with_index(side_nav(@socket, @current_user)), @current_user do %>
              <details
                open={is_default_opened?}
                class="group cursor-pointer open:border-blue-planning-300/50"
              >
                <summary class="flex justify-between items-center uppercase font-bold px-4 py-3 tracking-widest text-xs flex-shrink-0 whitespace-nowrap group cursor-pointer group-open:bg-gray-100/80 group-open:text-blue-planning-300">
                  <span class="mr-2"><%= heading %></span>
                  <.icon
                    name="down"
                    class="text-blue-planning-300 w-4 h-4 stroke-current stroke-2 text-base flex-shrink-0 group-open:rotate-180"
                  />
                </summary>
                <%= for {%{title: title, icon: icon, path: path}, secondary_index} <- Enum.with_index(items) do %>
                  <.nav_link
                    title={title}
                    to={path}
                    socket={@socket}
                    live_action={@live_action}
                    current_user={@current_user}
                    class="text-sm px-4 flex items-center py-2.5 whitespace-nowrap text-base-250 transition-all hover:bg-blue-planning-100"
                    active_class="bg-blue-planning-100 text-black font-bold"
                  >
                    <div
                      class="inline"
                      phx-hook="Tooltip"
                      data-hint={title}
                      data-position="right"
                      id={"tippy#{primary_index}#{secondary_index}"}
                    >
                      <.icon name={icon} class="text-black inline-block w-5 h-5 mr-2 shrink-0" />
                    </div>
                    <span><%= title %></span>
                  </.nav_link>
                <% end %>
              </details>
            <% end %>
            <.nav_link
              title="Settings"
              to={~p"/users/setting"}
              socket={@socket}
              live_action={@live_action}
              current_user={@current_user}
              class="text-sm px-4 flex items-center py-2.5 whitespace-nowrap text-base-250 transition-all hover:bg-blue-planning-100"
              active_class="bg-blue-planning-100 text-black font-bold"
            >
              <div
                class="inline"
                phx-hook="Tooltip"
                data-hint="Settings"
                data-position="right"
                id="tippysettings"
              >
                <.icon name="settings" class="inline-block w-5 h-5 mr-2 text-black shrink-0" />
              </div>
              <span>Settings</span>
            </.nav_link>
          </nav>
          <div class="mt-auto">
            <%= if !is_nil(@onboarding_percentage) && @onboarding_percentage != 100 do %>
              <.link navigate={~p"/users/welcome"}>
                <div class="px-4 py-2.5 js--onboard-card" id="sidebar-onboarding">
                  <div class="border p-1.5 rounded-lg">
                    <h3 class="font-bold">Getting Started Checklist</h3>
                    <div class="flex items-center gap-2 justify-between">
                      <progress
                        class="progress w-full mt-3 mb-4 [&::-webkit-progress-bar]:rounded-lg [&::-webkit-progress-value]:rounded-lg [&::-webkit-progress-bar]:bg-gray-100 [&::-webkit-progress-value]:bg-green-finances-200 [&::-moz-progress-bar]:bg-green-finances-200 transition-all"
                        value={"#{@onboarding_percentage}"}
                        max="100"
                      >
                        <%= @onboarding_percentage %>%
                      </progress>
                      <span class="font-bold text-green-finances-200 js--percentage">
                        <%= @onboarding_percentage %>%
                      </span>
                    </div>
                    <div class="flex justify-end">
                      <span class="link">View</span>
                    </div>
                  </div>
                </div>
              </.link>
            <% else %>
              <.nav_link
                title="Onboarding"
                to={~p"/users/welcome"}
                socket={@socket}
                live_action={@live_action}
                current_user={@current_user}
                target="_blank"
                class="text-sm px-4 flex items-center py-2.5 whitespace-nowrap text-base-250 transition-all hover:bg-blue-planning-100"
                active_class="bg-blue-planning-100 text-black font-bold"
              >
                <div
                  class="inline"
                  phx-hook="Tooltip"
                  data-hint="Getting started"
                  data-position="right"
                  id="tippyonboarding"
                >
                  <.icon name="sparkles" class="inline-block w-5 h-5 mr-2 text-black shrink-0" />
                </div>
                <span>Getting started</span>
              </.nav_link>
            <% end %>
            <%= if @current_user && Application.get_env(:todoplace, :intercom_id) do %>
              <.nav_link
                title="Help"
                to="#help"
                socket={@socket}
                live_action={@live_action}
                current_user={@current_user}
                class="text-sm px-4 flex items-center py-2.5 whitespace-nowrap text-base-250 transition-all hover:bg-blue-planning-100 open-help"
                active_class="bg-blue-planning-100 text-black font-bold"
              >
                <div
                  class="inline"
                  phx-hook="Tooltip"
                  data-hint="Help"
                  data-position="right"
                  id="tippyhelp"
                >
                  <.icon name="question-mark" class="inline-block w-5 h-5 mr-2 text-black shrink-0" />
                </div>
                <span>Help</span>
              </.nav_link>
            <% else %>
              <.nav_link
                title="Help"
                to="https://support.todoplace.com/"
                socket={@socket}
                live_action={@live_action}
                current_user={@current_user}
                class="text-sm px-4 flex items-center py-2.5 whitespace-nowrap text-base-250 transition-all hover:bg-blue-planning-100 open-help"
                active_class="bg-blue-planning-100 text-black font-bold"
              >
                <div
                  class="inline"
                  phx-hook="Tooltip"
                  data-hint="Help"
                  data-position="right"
                  id="tippyhelp"
                >
                  <.icon name="question-mark" class="inline-block w-5 h-5 mr-2 text-black shrink-0" />
                </div>
                <span>Help</span>
              </.nav_link>
            <% end %>
            <button
              phx-click="collapse"
              phx-target={@myself}
              data-drawer-type="desktop"
              data-drawer-target="default-sidebar"
              data-drawer-toggle="default-sidebar"
              aria-controls="default-sidebar"
              type="button"
              class="text-sm px-4 sm:flex items-center py-2.5 whitespace-nowrap text-base-250 transition-all hover:bg-blue-planning-100 w-full hidden"
            >
              <span class="sr-only">Open sidebar</span>
              <div
                class="inline"
                phx-hook="Tooltip"
                data-hint="Collapse"
                data-position="right"
                id="tippycollapse"
              >
                <.icon
                  name="collapse"
                  class="inline-block w-5 h-5 mr-2 text-black shrink-0 transition-all"
                />
              </div>
              <span>Collapse</span>
            </button>
          </div>
        </div>
      </aside>
    </div>
    """
  end

  def initials_menu(assigns) do
    assigns =
      Enum.into(assigns, %{})

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

            <.form :let={f} for={%{}} as={:sign_out} action={~p"/users/log_out"} method="delete">
              <div id="user-agent" phx-hook="UserAgent"></div>
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

  def get_classes_for_main(%{onboarding: onboarding}) do
    %{
      "large-margin" => Map.get(onboarding, :sidebar_open_preference, true),
      "small-margin" => !Map.get(onboarding, :sidebar_open_preference, true)
    }
  end

  def get_classes_for_main(_) do
    %{
      "large-margin" => true
    }
  end

  defp is_drawer_open?(%{current_user: %{onboarding: onboarding}}) do
    Map.get(onboarding, :sidebar_open_preference, true)
  end

  defp is_drawer_open?(_) do
    true
  end

  def side_nav(socket, current_user) do
    [
      %{
        heading: "Monetize",
        is_default_opened?: true,
        items: [
          %{title: "Leads", icon: "three-people", path: ~p"/leads"},
          %{
            title: "Jobs",
            icon: "camera-check",
            path: ~p"/jobs"
          },
          %{
            title: "Galleries",
            icon: "upload",
            path: ~p"/galleries"
          },
          %{
            title: "Booking Events",
            icon: "calendar",
            path: ~p"/booking-events"
          },
          %{
            title: "Clients",
            icon: "client-icon",
            path: ~p"/clients"
          }
        ]
      },
      %{
        heading: "Manage",
        is_default_opened?: true,
        items: get_manage_items(socket, current_user)
      },
      %{
        heading: "Admin & Docs",
        is_default_opened?: true,
        items: [
          %{
            title: "Automations (Beta)",
            icon: "play-icon",
            path: ~p"/email-automations"
          },
          %{
            title: "Packages",
            icon: "package",
            path: ~p"/package_templates"
          },
          %{
            title: "Contracts",
            icon: "contract",
            path: ~p"/contracts"
          },
          %{
            title: "Questionnaires",
            icon: "questionnaire",
            path: ~p"/questionnaires"
          }
        ]
      }
    ]
  end

  defp get_manage_items(socket, current_user) do
    base_items = [
      %{
        title: "Inbox",
        icon: "envelope",
        path: ~p"/inbox"
      },
      %{
        title: "Calendar",
        icon: "calendar",
        path: ~p"/calendar"
      },
      %{title: "Marketing", icon: "bullhorn", path: ~p"/marketing"}
    ]

    if FunWithFlags.enabled?(:can_manage_finances, for: current_user) do
      base_items ++
        [
          %{
            title: "Finances",
            icon: "money-bags",
            path: ~p"/finances"
          }
        ]
    else
      base_items
    end
  end

  def main_header(assigns) do
    ~H"""
    <.live_component module={__MODULE__} id={assigns[:id] || "application-sidebar"} {assigns} />
    """
  end

  defp get_percentage(%{current_user: user}) do
    get_percentage_completed_count(user)
  end

  def organization_logo(assigns) do
    ~H"""
    <%= case Todoplace.Profiles.logo_url(@organization) do %>
      <% nil -> %>
        <h1 class="text-xl font-bold">
          <%= String.trim(@organization.name) |> String.first() |> String.upcase() %>
        </h1>
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
        <img
          class="inline-block w-9 h-9 mr-4 rounded-lg border border-black text-blue-planning-300"
          src={@url}
        />
      <% else %>
        <div class="rounded-lg w-9 h-9 border border-black text-blue-planning-300 mr-4 flex items-center justify-center">
          <h1 class="">
            <%= String.trim(@organization.name) |> String.first() |> String.upcase() %>
          </h1>
        </div>
      <% end %>
      <%= @organization.name %>
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
