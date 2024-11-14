defmodule TodoplaceWeb.InviteLive.Show do
  use TodoplaceWeb, live_view: [layout: :onboarding]

  import Phoenix.HTML.Form
  alias Todoplace.InviteToken
  alias Todoplace.Repo
  alias Todoplace.Accounts.User

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case InviteToken.validate_invite_token(token) do
      {:ok, invitation} ->
        socket
        |> assign(trigger_submit: false)
        |> assign(invitation: invitation)
        |> assign(token: token)

      _ ->
        socket
        |> put_flash(:error, "invite link is invalid or expired")
        |> push_redirect(to: ~p"/home")
    end
    |> ok()
  end

  @impl true
  def handle_event("save", _params, socket) do
    token = socket.assigns.token

    case fetch_user_by_token(token) do
      {:ok, user} ->
        socket
        |> push_redirect(to: ~p"/users/log_in?token=#{token}")
        |> noreply()

      :error ->
        socket
        |> push_redirect(to: ~p"/users/register?token=#{token}")
        |> noreply()
    end
  end

  defp fetch_user_by_token(token) do
    with {:ok, invite_token} <- Todoplace.InviteToken.get_by_token(token),
         user <- Repo.get_by(User, email: invite_token.email),
         true <- user != nil do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={
      classes([
        "flex flex-col items-center justify-center w-screen min-h-screen p-5",
        "bg-orange-inbox-200"
      ])
    }>
      <div class="container px-6 pt-8 pb-6 bg-white rounded-lg shadow-md max-w-screen-sm sm:p-14">
        <%!-- <div class="flex items-end justify-between sm:items-center">
          <.icon name="logo-shoot-higher" class="w-32 h-12 sm:h-20 sm:w-48" />
        </div> --%>
        <div>
          <div class="font-semibold p-2 text-blue-400 text-lg">
            You are invited to the following organization.
          </div>
          <div class="border-2 p-2">
            <div class="flex items-center gap-4">
              <span class="font-semibold">Organization:</span>
              <span><%= @invitation.organization.name %></span>
              <.form
                :let={f}
                for={%{}}
                action={~p"/users/login_by_invite"}
                phx-submit="save"
                phx-trigger-action={@trigger_submit}
                class="flex flex-col"
              >
                <%= hidden_input(f, :token, value: @invitation.token) %>
                <div class="flex mt-auto">
                  <%= submit("Join",
                    class: "btn-primary sm:flex-1 px-6 sm:px-10 flex-grow",
                    phx_disable_with: "Saving..."
                  ) %>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
