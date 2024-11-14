defmodule TodoplaceWeb.UserControlsComponent do
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.LiveHelpers
  alias Phoenix.LiveView.JS
  alias Todoplace.Accounts.User

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="flex gap-3 w-1/4 items-center justify-end text-white z-50">
      <.icon name="question-mark" class="w-5 h-5 text-black fill-black" />
      <div
        id="settings-menu-wrapper"
        phx-click-away={JS.set_attribute({"style", "display: none"}, to: "#settings-menu")}
        phx-click={JS.toggle(to: "#settings-menu")}
      >
        <.icon name="settings" class="w-5 h-5 text-black fill-black" />
        <!-- Settings Menu -->
        <div
          id="settings-menu"
          class="hidden absolute right-0 mt-2 w-48 bg-white shadow-md rounded-md z-50"
        >
          <ul class="py-1">
            <li>
              <.link navigate={~p"/profile"} class="block px-4 py-2 text-gray-700 hover:bg-gray-100">
                Profile
              </.link>
            </li>
            <li>
              <div phx-click="system-settings" class="block px-4 py-2 text-gray-700 hover:bg-gray-100">
                Settings
              </div>
            </li>
          </ul>
        </div>
      </div>
      <div class="w-9 h-9 rounded-full bg-red-200 mr-4 relative border">
        <.initials_menu {assigns} />
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
      <%= if @current_user_data.current_user do %>
        <div
          id="initials-menu-inner-content"
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
              <.initials_circle user={@current_user_data.current_user} />
              <div class="ml-2 font-bold">Account</div>
            </.link>

            <.form :let={f} for={%{}} as={:sign_out} action={~p"/users/log_out"} method="delete">
              <div id="user-agent" phx-hook="UserAgent"></div>
              <%= submit("Logout", class: "text-center py-2 w-full") %>
            </.form>
          </div>
        </div>
        <div
          class="flex flex-col items-center justify-center text-sm text-base-300 bg-gray-100 rounded-full w-9 h-9 pb-0.5"
          title={@current_user_data.current_user.name}
        >
          <%= User.initials(@current_user_data.current_user) %>
        </div>
      <% end %>
    </div>
    """
  end
end
