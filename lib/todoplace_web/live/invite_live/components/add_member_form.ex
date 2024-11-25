defmodule TodoplaceWeb.InviteLive.AddMemberForm do
  use TodoplaceWeb, :live_component

  import Phoenix.HTML.Form
  import Ecto.Changeset
  import TodoplaceWeb.LiveModal, only: [close_x: 1, footer: 1]

  alias Todoplace.Accounts.{User, UserOrganization}
  alias Todoplace.{Accounts, Organization}

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(onboarding_type: nil)
    |> assign(changeset: changeset(%{}))
    |> assign(organization_id: assigns[:organization_id])
    |> ok()
  end

  @impl true
  def handle_event(
        "validate",
        %{"user" => user_params},
        %{assigns: %{organization_id: organization_id}} = socket
      ) do
    changeset = changeset(user_params)
    unique? = Accounts.email_for_organization(user_params["email"], organization_id)
    changeset = (unique? && changeset) || add_error(changeset, :email, "already exist")

    socket
    |> assign(changeset: changeset)
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        %{"user" => %{"email" => email, "organization_id" => organization_id} = params},
        %{assigns: %{organization_id: organization_id}} = socket
      ) do
    organization = Todoplace.Accounts.get_organization(organization_id)

    case Todoplace.InviteToken.generate_invite_token(email, socket.assigns.organization_id) do
      {:ok, invite_token} ->
        Todoplace.Cache.refresh_organization_cache(organization.id)
        Accounts.update_user_cache_by_email(email)

        url = url(~p"/join_organization/#{invite_token.token}")

        Todoplace.Notifiers.UserNotifier.deliver_join_organization(
          organization.name,
          email,
          invite_token.token
        )

        socket
        |> close_modal
        |> noreply()

      {:error, _reason} ->
        socket
        |> close_modal
        |> noreply()
    end
  end

  defp changeset(user_params, action \\ :validate) do
    %User{}
    |> Accounts.change_invite_user(user_params)
    |> Map.put(:action, action)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col modal p-30">
      <div class="flex items-start justify-between flex-shrink-0">
        <h1 class="mb-4 text-3xl font-bold">
          Invite User
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
      <.form
        :let={f}
        for={@changeset}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
        class="flex flex-col"
      >
        <%= labeled_input(f, :email,
          type: :email_input,
          placeholder: "jack.nimble@example.com",
          phx_debounce: "500",
          wrapper_class: "mt-4"
        ) %>
        <%= hidden_input(f, :organization_id, value: @organization_id) %>
        <div class="flex flex-col py-6 bg-white gap-2 sm:flex-row-reverse">
          <button
            class="px-8 btn-primary"
            title="Save"
            disabled={!@changeset.valid?}
            phx-target={@myself}
          >
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
      </.form>
    </div>
    """
  end
end
