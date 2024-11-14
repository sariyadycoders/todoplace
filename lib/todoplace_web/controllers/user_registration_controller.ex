defmodule TodoplaceWeb.UserRegistrationController do
  import Todoplace.Zapier.User, only: [user_created_webhook: 1]

  use TodoplaceWeb, :controller

  alias Todoplace.{
    Accounts,
    OrganizationCard,
    GlobalSettings,
    Workers.PrefillSigningUpUser
  }

  alias TodoplaceWeb.UserAuth

  def create(%{req_cookies: cookies} = conn, %{"user" => user_params}) do
    device_id = cookies |> Map.get("user_agent") |> URI.decode_www_form()

    onboarding_flow_source =
      case user_params do
        %{"onboarding_flow_source" => onboarding_flow_source} -> [onboarding_flow_source]
        _ -> []
      end

    user_params =
      user_params
      |> Map.put_new("organization", %{
        organization_cards: OrganizationCard.for_new_changeset(),
        gs_gallery_products: GlobalSettings.gallery_products_params()
      })
      |> Map.put("onboarding_flow_source", onboarding_flow_source)
      |> Enum.into(Map.take(cookies, ["time_zone"]))

    user_params =
      case user_params do
        %{"organization_id" => organization_id, "token" => token} ->
          user_params
          |> Map.put("organization_id", organization_id)
          |> Map.put("token", token)

        _ ->
          user_params
      end

    Accounts.register_user(user_params)
    |> case do
      {:ok, user} ->
        # {:ok, _} =
        #   Accounts.deliver_user_confirmation_instructions(
        #     user,
        #     &url(~p"/users/confirm/#{&1}")
        #   )

        :ok = PrefillSigningUpUser.perform(user)

        add_user_to_external_tools(user)

        conn
        |> UserAuth.log_in_user(user, %{"device_id" => device_id})

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  defp add_user_to_external_tools(user) do
    %{
      list_ids: SendgridClient.get_all_client_list_env(),
      clients: [
        %{
          email: user.email,
          first_name: Accounts.User.first_name(user),
          last_name: Accounts.User.last_name(user),
          custom_fields: %{
            w4_N: user.id,
            w3_T: user.organization.name,
            w1_T: "pre_trial"
          }
        }
      ]
    }
    |> SendgridClient.add_clients()

    user_created_webhook(%{
      email: user.email,
      first_name: Accounts.User.first_name(user),
      last_name: Accounts.User.last_name(user)
    })
  end

  def login_by_invite(conn, %{"token" => token}) do
    case Accounts.accept_invite(token) do
      {:ok, %{user: user}} ->
        conn
        |> UserAuth.log_in_user(user)

      _ ->
        conn
        |> put_flash(
          :error,
          "invalid or expire"
        )
        |> redirect(to: "/")
    end
  end
end

defmodule TodoplaceWeb.UserRegistrationHTML do
  use TodoplaceWeb, :html
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]
  import TodoplaceWeb.ViewHelpers

  embed_templates "templates/*"
end
