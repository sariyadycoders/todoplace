defmodule TodoplaceWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use TodoplaceWeb, :controller
      use TodoplaceWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  import Ecto.Query

  def static_paths,
    do: [
      "assets",
      "fonts",
      "images",
      "favicon",
      "favicon.ico",
      "robots.txt",
      "css",
      "js",
      "static",
      "manifest.json",
      "firebase-logo.png"
    ]

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: TodoplaceWeb.Layouts]

      import Plug.Conn
      import TodoplaceWeb.Gettext
      import Todoplace.Cache
      unquote(verified_routes())
    end
  end

  defp modal_helpers do
    quote do
      @impl true
      def handle_event(
            "add-organization",
            _,
            %{assigns: %{current_user_data: user_data}} = socket
          ) do
        socket
        |> open_modal(TodoplaceWeb.OrganizationLive.AddOrganizationComponent, %{
          user_data: user_data
        })
        |> noreply()
      end

      @impl true
      def handle_event(
            "create-organization",
            _,
            %{assigns: %{current_user_data: user_data}} = socket
          ) do
        socket
        |> open_modal(TodoplaceWeb.OrganizationLive.CreateOrganizationComponent, %{
          user_data: user_data,
          organization_page: socket.view == TodoplaceWeb.OrganizationLive.Index
        })
        |> noreply()
      end

      @impl true
      def handle_event("set_current_path", %{"path" => path}, socket) do
        {:noreply, assign(socket, :current_path, path)}
      end

      def handle_event("new_notification", %{"title" => title, "body" => body}, socket) do
        # Assuming you have the user assigned to the socket
        user_id = socket.assigns.current_user.id

        # Check if the notification already exists for this user with the same body
        existing_notification =
          Todoplace.Accounts.Notification
          |> where([n], n.user_id == ^user_id and n.body == ^body)
          |> Todoplace.Repo.one()

        case existing_notification do
          nil ->
            # Insert the notification into the database if it doesn't already exist
            changeset =
              Todoplace.Accounts.Notification.changeset(%Todoplace.Accounts.Notification{}, %{
                "title" => title,
                "body" => body,
                # Associate with user
                "user_id" => user_id
              })

            case Todoplace.Repo.insert(changeset) do
              {:ok, _notification} ->
                # Query the total count of notifications for this user
                notification_count =
                  Todoplace.Accounts.Notification
                  |> where([n], n.user_id == ^user_id)
                  |> Todoplace.Repo.aggregate(:count, :id)

                # Assign the notification count to the socket
                send_update(TodoplaceWeb.OrganizationLive.AddOrganizationComponent,
                  id: "add-organization",
                  notification_count: notification_count
                )

              {:error, changeset} ->
                # Handle error if needed
                {:noreply, socket}
            end

          _notification ->
            # If notification already exists, you can handle it here (e.g., ignore or send a message)
            {:noreply, socket}
        end
      end

      @impl true
      def handle_event("system-settings", _, %{assigns: %{current_user_data: user_data}} = socket) do
        socket
        |> open_modal(TodoplaceWeb.Live.Admin.SystemSettings, %{
          user_data: user_data
        })
        |> noreply()
      end

      @impl true
      def handle_event("remove-from-selected-list", %{"id" => org_id}, socket) do
        org_id = String.to_integer(org_id)

        case Todoplace.Organization.toggle_org_status(socket.assigns.current_user.id, org_id) do
          {:ok, _organization} ->
            user_organizations =
              Todoplace.Organization.list_organizations_active(socket.assigns.current_user.id)

            Todoplace.Cache.refresh_current_user_cache(socket.assigns.current_user_data.session_token)

            Phoenix.PubSub.broadcast(
              Todoplace.PubSub,
              "organization:#{socket.assigns.current_user.id}",
              {:update_organization_nav, 1}
            )

            {:noreply, socket}

          {:error, changeset} ->
            {:noreply, assign(socket, :error_changeset, changeset)}
        end
      end

      def handle_info({:update_organization_nav, notification_count}, socket) do
        # Update the organizations in the socket assign
        send_update(TodoplaceWeb.Shared.Outerbar,
          id: "app-org-sidebar",
          notification_count: notification_count
        )

        {:noreply, assign(socket, :notification_count, notification_count)}
      end

      @impl true
      def handle_info(
            {:modal_pid, pid},
            %{assigns: %{queued_modal: {component, config}}} = socket
          ),
          do:
            socket
            |> assign(modal_pid: pid, queued_modal: nil)
            |> open_modal(component, config)
            |> noreply()

      @impl true
      def handle_info({:modal_pid, pid}, socket),
        do:
          socket
          |> assign(modal_pid: pid)
          |> noreply()
    end
  end

  def live_view(options \\ []) do
    options =
      case Keyword.get(options, :layout, "live") do
        false ->
          []

        name ->
          name = name |> to_string |> String.to_atom()
          [layout: {TodoplaceWeb.Layouts, name}]
      end

    quote do
      use Phoenix.LiveView, unquote(options)

      import TodoplaceWeb.{LiveViewHelpers, LiveHelpers, FormHelpers}
      import Todoplace.Cache

      unquote(html_helpers())
      unquote(modal_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent
      import TodoplaceWeb.LiveHelpers
      import TodoplaceWeb.FormHelpers
      import Todoplace.Cache

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      # import TodoplaceWeb.FormHelpers

      import TodoplaceWeb.CoreComponents, except: [header: 1, error: 1, button: 1, icon: 1]
      import TodoplaceWeb.Gettext

      import Phoenix.HTML
      import Phoenix.HTML.Form
      use PhoenixHTMLHelpers

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS
      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TodoplaceWeb.Endpoint,
        router: TodoplaceWeb.Router,
        statics: TodoplaceWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defmacro __using__([{which, opts}]) do
    apply(__MODULE__, which, [opts])
  end
end
