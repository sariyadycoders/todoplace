defmodule TodoplaceWeb.Live.Admin.SystemSettings do
  @moduledoc false
  use TodoplaceWeb, :live_component

  @tabs [
    %{label: "Notifications", id: :notifications},
    %{label: "Display", id: :display},
    %{label: "Sidebar", id: :sidebar},
    %{label: "Advanced", id: :advanced}
  ]

  # Default notifications data
  @initial_notifications %{
    desktop: "All new messages",
    desktop_sound: "Bing for messages, Calm for calls",
    email: "Immediately",
    keywords: "@team, @channel, @all"
  }

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      # Default active tab
      |> assign_new(:active_tab, fn -> :notifications end)
      # Default notification settings
      |> assign_new(:notifications, fn -> @initial_notifications end)
      # No field is being edited initially
      |> assign_new(:editing_field, fn -> nil end)
      |> assign(:tabs, @tabs)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col modal p-6">
      <!-- Modal header -->
      <div class="flex items-start justify-between">
        <h1 class="mb-4 text-3xl font-bold">Settings</h1>
        <button
          phx-click="modal"
          phx-value-action="close"
          title="close modal"
          type="button"
          class="p-2"
        >
          <.icon name="close-x" class="w-4 h-4 stroke-current" />
        </button>
      </div>
      <!-- Modal body with left-side tabs -->
      <div class="flex flex-row">
        <!-- Sidebar with tabs and explicit borders on top, right, and left -->
        <div class="w-1/4 bg-gray-100 p-4 border-t border-l border-r border-gray-300">
          <ul>
            <%= for tab <- @tabs do %>
              <li class="mb-2">
                <button
                  phx-click="change_tab"
                  phx-value-tab={tab.id}
                  phx-target={@myself}
                  class={"block w-full text-left px-4 py-2 rounded-lg mb-2 " <>
                    if @active_tab == tab.id, do: "bg-blue-planning-300 text-white", else: "hover:bg-blue-planning-100"}
                >
                  <%= tab.label %>
                </button>
              </li>
            <% end %>
          </ul>
        </div>
        <!-- Right content area -->
        <div class="w-3/4 p-4 border-t border-r border-gray-300 overflow-y-auto">
          <%= case @active_tab do %>
            <% :notifications -> %>
              <h3 class="text-lg font-medium">Notifications</h3>
              <div class="mt-4 space-y-4">
                <.render_notifications target={@myself} {assigns} />
              </div>
            <% :display -> %>
              <h3 class="text-lg font-medium">Display</h3>
              <div class="mt-4 space-y-4">
                <p>Manage your display settings here.</p>
              </div>
            <% :sidebar -> %>
              <h3 class="text-lg font-medium">Sidebar</h3>
              <div class="mt-4 space-y-4">
                <p>Manage your sidebar settings here.</p>
              </div>
            <% :advanced -> %>
              <h3 class="text-lg font-medium">Advanced</h3>
              <div class="mt-4 space-y-4">
                <p>Manage advanced system settings here.</p>
              </div>
          <% end %>
        </div>
      </div>

      <div>
        <div class="flex flex-col py-6 bg-white gap-2 sm:flex-row-reverse">
          <button class="px-8 btn-primary" title="Save">
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

  defp render_notifications(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Card for Desktop and Mobile Notifications -->
      <div class={"bg-white shadow rounded-lg border p-4 " <> if @editing_field == :desktop, do: "bg-blue-50", else: ""}>
        <!-- Content Row -->
        <div class="flex justify-between items-center border-b border-gray-200 pb-2 mb-2">
          <p class="text-lg font-semibold">Desktop and mobile notifications:</p>
          <%= if @editing_field == :desktop do %>
            <!-- Edit mode, so no edit button -->
          <% else %>
            <button
              phx-click="edit"
              phx-target={@target}
              phx-value-field="desktop"
              class="text-blue-500 hover:bg-blue-100 hover:text-blue-700 px-3 py-1 rounded"
            >
              Edit
            </button>
          <% end %>
        </div>
        <!-- Display Value -->
        <p class="text-gray-600"><%= @notifications.desktop %></p>
        <!-- Edit Form - Aligned to right, below content, with background change -->
        <%= if @editing_field == :desktop do %>
          <div class="flex justify-end mt-2">
            <.edit_notifications_form field="desktop" target={@target} value={@notifications.desktop} />
          </div>
        <% end %>
      </div>
      <!-- Card for Desktop Notification Sounds -->
      <div class={"bg-white shadow rounded-lg border p-4 " <> if @editing_field == :desktop_sound, do: "bg-blue-50", else: ""}>
        <!-- Content Row -->
        <div class="flex justify-between items-center border-b border-gray-200 pb-2 mb-2">
          <p class="text-lg font-semibold">Desktop notification sounds:</p>
          <%= if @editing_field == :desktop_sound do %>
            <!-- Edit mode, so no edit button -->
          <% else %>
            <button
              phx-click="edit"
              phx-target={@target}
              phx-value-field="desktop_sound"
              class="text-blue-500 hover:bg-blue-100 hover:text-blue-700 px-3 py-1 rounded"
            >
              Edit
            </button>
          <% end %>
        </div>
        <!-- Display Value -->
        <p class="text-gray-600"><%= @notifications.desktop_sound %></p>
        <!-- Edit Form - Aligned to right, below content, with background change -->
        <%= if @editing_field == :desktop_sound do %>
          <div class="flex justify-end mt-2">
            <.edit_notifications_form
              field="desktop_sound"
              target={@target}
              value={@notifications.desktop_sound}
            />
          </div>
        <% end %>
      </div>
      <!-- Card for Email Notifications -->
      <div class={"bg-white shadow rounded-lg border p-4 " <> if @editing_field == :email, do: "bg-blue-50", else: ""}>
        <!-- Content Row -->
        <div class="flex justify-between items-center border-b border-gray-200 pb-2 mb-2">
          <p class="text-lg font-semibold">Email notifications:</p>
          <%= if @editing_field == :email do %>
            <!-- Edit mode, so no edit button -->
          <% else %>
            <button
              phx-click="edit"
              phx-target={@target}
              phx-value-field="email"
              class="text-blue-500 hover:bg-blue-100 hover:text-blue-700 px-3 py-1 rounded"
            >
              Edit
            </button>
          <% end %>
        </div>
        <!-- Display Value -->
        <p class="text-gray-600"><%= @notifications.email %></p>
        <!-- Edit Form - Aligned to right, below content, with background change -->
        <%= if @editing_field == :email do %>
          <div class="flex justify-end mt-2">
            <.edit_notifications_form field="email" target={@target} value={@notifications.email} />
          </div>
        <% end %>
      </div>
      <!-- Card for Keywords That Trigger Notifications -->
      <div class={"bg-white shadow rounded-lg border p-4 " <> if @editing_field == :keywords, do: "bg-blue-50", else: ""}>
        <!-- Content Row -->
        <div class="flex justify-between items-center border-b border-gray-200 pb-2 mb-2">
          <p class="text-lg font-semibold">Keywords that trigger notifications:</p>
          <%= if @editing_field == :keywords do %>
            <!-- Edit mode, so no edit button -->
          <% else %>
            <button
              phx-click="edit"
              phx-target={@target}
              phx-value-field="keywords"
              class="text-blue-500 hover:bg-blue-100 hover:text-blue-700 px-3 py-1 rounded"
            >
              Edit
            </button>
          <% end %>
        </div>
        <!-- Display Value -->
        <p class="text-gray-600"><%= @notifications.keywords %></p>
        <!-- Edit Form - Aligned to right, below content, with background change -->
        <%= if @editing_field == :keywords do %>
          <div class="flex justify-end mt-2">
            <.edit_notifications_form
              field="keywords"
              target={@target}
              value={@notifications.keywords}
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp edit_notifications_form(assigns) do
    ~H"""
    <form phx-submit="save_notifications" phx-target={@target} class="mt-2 space-y-4">
      <!-- Input field -->
      <div>
        <input type="text" name={@field} value={@value} class="border w-full px-2 py-1 rounded" />
      </div>
      <!-- Buttons aligned at the bottom -->
      <div class="flex justify-end space-x-2">
        <button type="button" phx-click="cancel_edit" phx-target={@target} class="btn-secondary">
          Cancel
        </button>
        <button type="submit" class="btn-primary">
          Save
        </button>
      </div>
    </form>
    """
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    {:noreply, assign(socket, :active_tab, tab_atom)}
  end

  @impl true
  def handle_event("edit", %{"field" => field}, socket) do
    {:noreply, assign(socket, :editing_field, String.to_existing_atom(field))}
  end

  @impl true
  def handle_event("save_notifications", %{"desktop" => desktop}, socket) do
    notifications = Map.put(socket.assigns.notifications, :desktop, desktop)
    {:noreply, socket |> assign(:notifications, notifications) |> assign(:editing_field, nil)}
  end

  def handle_event("save_notifications", %{"desktop_sound" => desktop_sound}, socket) do
    notifications = Map.put(socket.assigns.notifications, :desktop_sound, desktop_sound)
    {:noreply, socket |> assign(:notifications, notifications) |> assign(:editing_field, nil)}
  end

  def handle_event("save_notifications", %{"email" => email}, socket) do
    notifications = Map.put(socket.assigns.notifications, :email, email)
    {:noreply, socket |> assign(:notifications, notifications) |> assign(:editing_field, nil)}
  end

  def handle_event("save_notifications", %{"keywords" => keywords}, socket) do
    notifications = Map.put(socket.assigns.notifications, :keywords, keywords)
    {:noreply, socket |> assign(:notifications, notifications) |> assign(:editing_field, nil)}
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing_field, nil)}
  end
end
