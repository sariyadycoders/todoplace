defmodule Todoplace.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  import Todoplace.Zapier.User, only: [user_created_webhook: 1]
  alias Ecto.Multi

  alias Todoplace.{
    Repo,
    Organization,
    Accounts.User,
    Accounts.UserToken,
    OrganizationCard,
    Notifiers.UserNotifier,
    GlobalSettings,
    Accounts.UserInvitation,
    UserOrganization,
    Organization,
    UsersAuthMethod
  }

  ## Database getters

  def get_organization(organization_id) do
    Repo.get(Organization, organization_id)
  end

  def toggle_organization_status(organization, is_active) do
    organization_users = get_users_of_organization(organization.id)

    Multi.new()
    |> update_organization_status(organization, is_active)
    |> update_users_organizations_status(organization.id, is_active)
    |> handle_users_on_org_deactivation(organization.id, organization_users, is_active)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        organization_users
        |> update_organization_user_cache()

        Todoplace.Cache.refresh_organization_cache(organization.id)
        {:ok, "inactive"}

      _ ->
        {:error, "something happend wrong"}
    end
  end

  def update_organization_user_cache(users) do
    Enum.map(users, fn user -> update_user_cache(user.id) end)
  end

  def get_users_of_organization(id) do
    organization = get_orgnization(id)

    Enum.map(organization.organization_users, & &1.user)
  end

  def get_orgnization(id) do
    Organization
    |> Repo.get!(id)
    |> Repo.preload(organization_users: [user: [:user_organizations]])
  end

  @spec get_user_by_email(String.t()) :: User.t() | nil
  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_organization(user_id, organization_id) do
    Repo.get_by(UserOrganization, user_id: user_id, organization_id: organization_id)
  end

  def update_user(user_id, attrs) do
    Repo.get_by(User, id: user_id)
    |> case do
      nil ->
        {:error, "invalid user"}

      user ->
        User.organization_changeset(user, attrs)
        |> Repo.update()
    end
  end

  def user_active_organization(user_id, status) do
    from(uo in UserOrganization,
      join: o in Organization,
      on: o.id == uo.organization_id,
      where: uo.user_id == ^user_id and uo.status == ^status,
      select: o
    )
    |> Repo.all()
  end

  def create_user_organization(params) do
    %UserOrganization{}
    |> UserOrganization.changeset(params)
    |> Repo.insert()
  end

  def update_user_cache_by_email(email) do
    with %User{} = user <- get_user_by_email(email),
         %UserToken{token: token} <- UserToken.get_user_token_by_user_id(user.id) do
      Todoplace.Cache.update_log_in_user_cache(token)
    else
      _ ->
        :user_not_log_in
    end
  end

  def update_user_cache(user_id) do
    case UserToken.get_user_token_by_user_id(user_id) do
      %UserToken{token: token} -> Todoplace.Cache.update_log_in_user_cache(token)
      _ -> {:user_not_log_in, user_id}
    end
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email) |> Repo.preload([:user_organizations])
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a user by stripe customer id.

  ## Examples

      iex> get_user_by_stripe_customer_id("cus_1234")
      %User{}

      iex> get_user_by_stripe_customer_id("cus_invalid")
      nil

  """
  def get_user_by_stripe_customer_id(stripe_customer_id)
      when is_binary(stripe_customer_id) do
    Repo.get_by(User, stripe_customer_id: stripe_customer_id)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """

  def register_user(attrs) do
    organization_id = Map.get(attrs, "organization_id")
    token = Map.get(attrs, "token")

    Multi.new()
    |> Multi.insert(:user, User.registration_changeset(%User{}, attrs))
    |> Multi.insert(:user_auth_method, fn %{user: user} ->
      %UsersAuthMethod{}
      |> UsersAuthMethod.changeset(%{user_id: user.id, auth_method_name: "email"})
    end)
    |> Multi.insert(:user_organization, fn %{user: user} ->
      %UserOrganization{}
      |> UserOrganization.changeset(%{
        user_id: user.id,
        organization_id: user.organization_id,
        role: "admin",
        status: "Joined"
      })
    end)
    |> Multi.run(:organization, fn _repo, %{user: user} ->
      if token do
        Todoplace.InviteToken.mark_as_used(token)
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} ->
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset = user |> User.email_changeset(%{email: email}) |> User.confirm_changeset()

    Multi.new()
    |> Multi.update(:user, changeset)
    |> Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, [context]))
  end

  @doc """
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_update_email_instructions(user, current_email, &Routes.user_update_email_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Multi.new()
    |> Multi.update(:user, changeset)
    |> Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user, device_id) do
    user.id
    |> UserToken.get_user_token_by_user_id()
    |> case do
      nil ->
        {token, user_token} = UserToken.build_session_token(user)

        %UserToken{user_token | devices: [device_id]}
        |> Repo.insert!()

        token

      %{token: token, devices: devices} = user_token ->
        if device_id in devices do
          token
        else
          UserToken.changeset(user_token, %{devices: [device_id | devices]})
          |> Repo.update!()

          token
        end
    end
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    from(user in Todoplace.Accounts.User,
      where: user.id in subquery(query),
      join: org in assoc(user, :organization),
      left_join: subscription in assoc(user, :subscription),
      preload: [
        :nylas_detail,
        :subscription,
        organization: [:organization_job_types],
        user_organizations: ^from(uo in Todoplace.UserOrganization, where: uo.status == "Joined")
      ]
    )
    |> Repo.one()
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token, device_id) do
    UserToken.token_and_context_query(token, "session")
    |> Repo.one()
    |> case do
      %{devices: [device]} = user_token when device == device_id ->
        Repo.delete!(user_token)
        Todoplace.Cache.delete_user_data(token)

      %{devices: devices} = user_token ->
        updated_devices = List.delete(devices, device_id)

        UserToken.changeset(user_token, %{devices: updated_devices})
        |> Repo.update!()
    end
  end

  ## Confirmation

  @doc """
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &Routes.user_confirmation_url(conn, :confirm, &1))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &Routes.user_confirmation_url(conn, :confirm, &1))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Multi.new()
    |> Multi.update(:user, User.confirm_changeset(user))
    |> Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &Routes.user_reset_password_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  defdelegate deliver_provider_auth_instructions(user, path), to: UserNotifier

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @spec reset_user_password(
          %{
            :__struct__ => atom | %{:__changeset__ => map, optional(any) => any},
            :id => any,
            optional(atom) => any
          },
          :invalid | %{optional(:__struct__) => none, optional(atom | binary) => any}
        ) :: {:error, any} | {:ok, any}
  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    user_token = UserToken.get_user_token_by_user_id(user.id)

    Multi.new()
    |> Multi.update(:user, User.password_changeset(user, attrs))
    |> Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} ->
        Repo.get_by(UsersAuthMethod, user_id: user.id, auth_method_name: "email")
        |> case do
          nil ->
            {:ok, _} =
              %UsersAuthMethod{}
              |> UsersAuthMethod.changeset(%{user_id: user.id, auth_method_name: "email"})
              |> Repo.insert()

            {:ok, user}

          _ ->
            {:ok, user}
        end

        case user_token do
          nil -> :skip
          %UserToken{token: token} -> Todoplace.Cache.delete_user_data(token)
        end

        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  def user_from_auth(
        %Ueberauth.Auth{provider: provider, info: %Ueberauth.Auth.Info{name: name, email: email}} =
          auth,
        time_zone,
        url,
        onboarding_flow_source \\ []
      ) do
    case Repo.get_by(User, email: email) do
      nil ->
        Multi.new()
        |> Multi.insert(
          :user,
          User.registration_changeset(
            %User{},
            %{
              email: email,
              name: name,
              time_zone: time_zone,
              onboarding_flow_source: onboarding_flow_source,
              organization: %{
                organization_cards: OrganizationCard.for_new_changeset(),
                gs_gallery_products: GlobalSettings.gallery_products_params()
              }
            },
            password: false
          )
          |> Ecto.Changeset.put_change(:sign_up_auth_provider, provider)
        )
        |> Multi.insert(:user_organization, fn %{user: user} ->
          params = %{
            user_id: user.id,
            organization_id: user.organization_id,
            role: "admin",
            status: "Joined"
          }

          %UserOrganization{}
          |> UserOrganization.changeset(params)
        end)
        |> Multi.insert(:user_auth_method, fn %{user: user} ->
          params = %{
            user_id: user.id,
            provider_user_id: auth.uid,
            auth_method_name: Atom.to_string(provider)
          }

          %UsersAuthMethod{}
          |> UsersAuthMethod.changeset(params)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{user: user}} ->
            deliver_user_reset_password_instructions(user, url)
            add_auth_user_to_sendgrid(user)
            {:ok, user}

          {:error, :user, changeset, _} ->
            {:error, changeset}
        end

      user ->
        Repo.get_by(UsersAuthMethod, user_id: user.id, auth_method_name: Atom.to_string(provider))
        |> case do
          nil ->
            params = %{
              user_id: user.id,
              provider_user_id: auth.uid,
              auth_method_name: Atom.to_string(provider)
            }

            %UsersAuthMethod{}
            |> UsersAuthMethod.changeset(params)
            |> Repo.insert()

            {:ok, user}

          _ ->
            {:ok, user}
        end
    end
  end

  def generate_password(length \\ 20) do
    :crypto.strong_rand_bytes(length) |> Base.encode64() |> binary_part(0, length)
  end

  defp add_auth_user_to_sendgrid(user) do
    %{
      list_ids: SendgridClient.get_all_client_list_env(),
      clients: [
        %{
          email: user.email,
          first_name: User.first_name(user),
          last_name: User.last_name(user),
          custom_fields: %{
            w4_N: user.id,
            w1_T: "pre_trial"
          }
        }
      ]
    }
    |> SendgridClient.add_clients()

    user_created_webhook(%{
      email: user.email,
      first_name: User.first_name(user),
      last_name: User.last_name(user)
    })

    {:ok, user}
  end

  @spec preload_settings(User.t()) :: User.t()
  def preload_settings(%User{} = user) do
    Repo.preload(user, [[organization: :address], :rewardful_affiliate], force: true)
  end

  def valid_invite_token(token) do
    with %UserInvitation{} = invitation <-
           Repo.get_by(UserInvitation, token: token, used: false) |> Repo.preload([:organization]),
         false <- token_expired?(invitation) do
      {:ok, invitation}
    else
      _ -> {:error, "invalid path"}
    end
  end

  def update_user_organization(user_id, organization_id) do
    user = Repo.get!(User, user_id)

    # Directly update the organization_id field
    user
    |> Ecto.Changeset.change(organization_id: organization_id)
    |> Repo.update()
  end

  defp update_organization_status(multi, organization, is_active) do
    multi
    |> Multi.update(
      :update_org,
      Organization.active_changeset(organization, %{is_active: is_active})
    )
  end

  defp update_users_organizations_status(multi, org_id, true) do
    multi
    |> Multi.update_all(
      :update_users_orgs_active,
      from(uo in UserOrganization, where: uo.organization_id == ^org_id),
      set: [org_status: :active]
    )
  end

  defp update_users_organizations_status(multi, org_id, false) do
    multi
    |> Multi.update_all(
      :update_users_orgs_active,
      from(uo in UserOrganization, where: uo.organization_id == ^org_id),
      set: [org_status: :deleted]
    )
  end

  defp handle_users_on_org_deactivation(multi, organization_id, organization_users, false) do
    Enum.reduce(organization_users, multi, fn user, multi ->
      case user.user_organizations do
        [_first, _second | _other] when user.organization_id == organization_id ->
          organization =
            Enum.find(
              user.user_organizations,
              &(&1.organization_id != organization_id && &1.org_status != :deleted)
            )

          multi
          |> switch_organization_by_multi(user, organization)

        _ ->
          multi
      end
    end)
  end

  defp handle_users_on_org_deactivation(multi, organization_id, organization_users, true) do
    Enum.reduce(organization_users, multi, fn user, multi ->
      case user.user_organizations do
        [_first, _second | _other] when user.organization_id != organization_id ->
          active_organization =
            Enum.find(
              user.user_organizations,
              &(&1.organization_id == user.organization_id && &1.org_status != :deleted)
            )

          organization =
            if active_organization,
              do: nil,
              else:
                Enum.find(
                  user.user_organizations,
                  &(&1.organization_id == organization_id)
                )

          multi
          |> switch_organization_by_multi(user, organization)

        _ ->
          multi
      end
    end)
  end

  defp switch_organization_by_multi(multi, user, nil), do: multi

  defp switch_organization_by_multi(multi, user, organization) do
    multi
    |> Multi.update(
      "switch_user_#{organization.organization_id}",
      User.organization_changeset(user, %{organization_id: organization.organization_id})
    )
  end

  def remove_user(user, organization_id) do
    user_id = user.id

    multi =
      Multi.new()
      |> Multi.update_all(
        :update_users_orgs_active,
        from(uo in UserOrganization,
          where: uo.organization_id == ^organization_id and uo.user_id == ^user_id
        ),
        set: [status: "removed"]
      )

    case user.user_organizations do
      [_first, _second | _other] when user.organization_id == organization_id ->
        organization =
          Enum.find(
            user.user_organizations,
            &(&1.organization_id != organization_id && &1.org_status != :deleted)
          )

        multi
        |> switch_organization_by_multi(user, organization)

      _ ->
        multi
    end
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        update_user_cache(user.id)
        Todoplace.Cache.refresh_organization_cache(organization_id)

        {:ok, "removed"}

      _ ->
        {:error, "something happend wrong"}
    end
  end

  def change_invite_user(%User{} = user, attrs \\ %{}) do
    User.invite_user_changeset(user, attrs, hash_password: false)
  end

  def email_for_organization(email, organization_id) do
    with %User{id: id} <- get_user_by_email(email),
         %UserOrganization{} <- get_user_organization(id, organization_id) do
      false
    else
      _ ->
        true
    end
  end

  defp token_expired?(invitation) do
    expiry_time = Timex.shift(invitation.inserted_at, days: 3)
    Timex.before?(expiry_time, Timex.now())
  end
end
