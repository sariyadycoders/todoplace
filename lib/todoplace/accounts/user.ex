defmodule Todoplace.Accounts.User do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  import TzExtra.Changeset

  alias Todoplace.{
    Onboardings.Onboarding,
    Subscription,
    SubscriptionEvent,
    Organization,
    NylasDetail,
    Rewardful,
    Accounts.User.Promotions,
    Repo,
    Accounts.UserPreference
  }

  @email_regex ~r/^(?!.*\.\.)(?!^[^\w]+)(?!.*[^\w]$)[^\s]+@[^\s]+\.[^\s]+$/
  @derive {Inspect, except: [:password]}

  schema "users" do
    field :confirmed_at, :naive_datetime
    field :deleted_at, :naive_datetime
    field :email, :string
    field :hashed_password, :string
    field :name, :string
    field :is_test_account, :boolean, default: false
    field :password, :string, virtual: true
    field :time_zone, :string
    field :sign_up_auth_provider, Ecto.Enum, values: [:google, :password], default: :password
    field :stripe_customer_id, :string
    embeds_one(:onboarding, Onboarding, on_replace: :update)
    field :onboarding_flow_source, {:array, :string}, default: []
    field :fcm_token, :string
    has_one(:subscription, Subscription)
    has_one(:subscription_event, SubscriptionEvent)
    has_one(:nylas_detail, NylasDetail)
    has_one(:rewardful_affiliate, Rewardful)
    has_many(:user_promotions, Promotions)
    belongs_to(:organization, Organization)
    has_many(:user_organizations, Todoplace.UserOrganization)
    # many_to_many :organizations, Todoplace.Organization, join_through: "users_organizations"
    field :role, :string
    has_one :user_preference, Todoplace.Accounts.UserPreference
    has_many :notifications, Todoplace.Accounts.Notification # Set up the relationship

    timestamps()
  end

  @spec registration_changeset(
          {map, map}
          | %{
              :__struct__ => atom | %{:__changeset__ => map, optional(any) => any},
              optional(atom) => any
            },
          map,
          keyword
        ) :: map
  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :password,
      :time_zone,
      :onboarding_flow_source,
      # Adding organization_id to cast list
      :organization_id
    ])
    |> validate_required([:name])
    |> validate_email()
    |> validate_password(opts)
    |> put_assoc(:nylas_detail, NylasDetail.changeset())
    |> maybe_preload_organization(attrs)
    |> maybe_cast_organization(attrs)
  end

  defp maybe_preload_organization(changeset, attrs) do
    case Map.get(attrs, "organization_id") do
      nil ->
        changeset

      organization_id ->
        organization = Repo.get!(Organization, organization_id)
        put_assoc(changeset, :organization, organization)
    end
  end

  defp maybe_cast_organization(changeset, attrs) do
    case Map.get(attrs, "organization_id") do
      nil ->
        changeset
        |> cast_assoc(:organization,
          with: &Organization.registration_changeset(&1, &2, get_field(changeset, :name))
        )

      _organization_id ->
        changeset
    end
  end

  def is_test_account_changeset(user \\ %__MODULE__{}, attrs \\ %{}) do
    user |> cast(attrs, [:is_test_account])
  end

  def new_session_changeset(user \\ %__MODULE__{}, attrs \\ %{}) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email_format()
    |> validate_required([:password])
  end

  def reset_password_changeset(user \\ %__MODULE__{}, attrs \\ %{}) do
    user
    |> cast(attrs, [:email])
    |> validate_email_format()
  end

  @spec validate_email_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_email_format(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, email_regex(), message: "is invalid")
    |> validate_length(:email, max: 160)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_email_format()
    |> unsafe_validate_unique(:email, Todoplace.Repo)
    |> unique_constraint(:email)
  end

  def email_regex(), do: @email_regex

  def validate_password(changeset, opts) do
    if Keyword.get(opts, :password, true) do
      changeset
      |> validate_required([:password])
      |> validate_length(:password, min: 12, max: 80)
      # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
      # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
      # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
      |> maybe_hash_password(opts)
    else
      changeset
    end
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
    |> validate_previous_sign_up_auth_provider(
      message: "must sign up with password to change email"
    )
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  def organization_changeset(user, attrs) do
    user
    |> cast(attrs, [:organization_id])
    |> validate_required([:organization_id])
    |> case do
      %{changes: %{organization_id: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :organization_id, "did not change")
    end
  end

  @doc """
  A user changeset for changing the name.
  Accept %Todoplace.Accounts.User{} as first argument and map as second argument.
  Returns %Ecto.Changeset{}
  """
  def name_changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> case do
      %{changes: %{name: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :name, "did not change")
    end
  end

  def validate_previous_sign_up_auth_provider(changeset, opts) do
    message = opts |> Keyword.get(:message, "is invalid")

    case changeset |> get_field(:sign_up_auth_provider) do
      :password ->
        changeset

      _ ->
        add_error(
          changeset,
          :sign_up_auth_provider,
          message
        )
    end
  end

  def time_zone_changeset(user, attrs) do
    user
    |> cast(attrs, [:time_zone])
    |> validate_required([:time_zone])
    |> validate_time_zone_identifier(:time_zone)
    |> case do
      %{changes: %{time_zone: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :time_zone, "did not change")
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  def complete_onboarding_changeset(user) do
    user
    |> change()
    |> put_embed(:onboarding, %{completed_at: DateTime.utc_now()})
  end

  def assign_stripe_customer_changeset(%__MODULE__{} = user, "" <> stripe_customer_id),
    do: user |> change(stripe_customer_id: stripe_customer_id)

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Todoplace.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password, field \\ :current_password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, field, "is not valid")
    end
  end

  def initials(%__MODULE__{name: name}) do
    case first_and_last_name(name) do
      {<<first_initial::binary-size(1), _::binary>>, <<last_initial::binary-size(1), _::binary>>} ->
        Enum.join([first_initial, last_initial])

      {<<first_initial::binary-size(2), _::binary>>, _} ->
        first_initial
    end
    |> String.upcase()
  end

  def first_name(%__MODULE__{name: name}), do: first_and_last_name(name) |> elem(0)

  def last_name(%__MODULE__{name: name}), do: first_and_last_name(name) |> elem(1)

  @doc """
  true if user has skipped or completed all onboarding steps.
  """
  def onboarded?(%__MODULE__{onboarding: nil}), do: false
  def onboarded?(%__MODULE__{onboarding: onboarding}), do: Onboarding.completed?(onboarding)

  def confirmed?(%__MODULE__{confirmed_at: nil, sign_up_auth_provider: :password}), do: false
  def confirmed?(%__MODULE__{}), do: true

  def put_new_attr(map, atom, value) when is_atom(atom) do
    Map.put_new(map, match_key_type(map).(atom), value)
  end

  def update_attr_in(map, path, f) do
    update_in(map, Enum.map(path, match_key_type(map)), f)
  end

  def get_user_preferences(user_id) do
    case Todoplace.Repo.get_by(Todoplace.Accounts.UserPreference, user_id: user_id) do
      nil ->
        # Create default preferences if none exist
        %Todoplace.Accounts.UserPreference{
          user_id: user_id,
          settings: %{menu_collapsed: false, theme: "light"}
        }
        |> Todoplace.Repo.insert!()

      preferences ->
        preferences
    end
  end

  def update_user_preference(user_id, new_settings) do
    user_preference = Todoplace.Repo.get_by(Todoplace.Accounts.UserPreference, user_id: user_id)

    changeset = Todoplace.Accounts.UserPreference.changeset(user_preference, %{settings: Map.merge(user_preference.settings, new_settings)})

    Todoplace.Repo.update(changeset)
  end

  def get_menu_state(user_id) do
    preferences = get_user_preferences(user_id)
    get_in(preferences.settings, ["menu_collapsed"])
  end

  def update_menu_collapsed(user_id, menu_collapsed) do
    user_preference = Repo.get_by(UserPreference, user_id: user_id) || %Todoplace.Accounts.UserPreference{user_id: user_id}

    updated_settings =
      user_preference.settings
      |> Map.put("menu_collapsed", menu_collapsed)

    user_preference
    |> UserPreference.changeset(%{settings: updated_settings})
    |> Repo.insert_or_update()
  end

  defp match_key_type(%{} = map) do
    case Map.keys(map) do
      [first_key | _] when is_atom(first_key) -> & &1
      _ -> &Atom.to_string/1
    end
  end

  defp first_and_last_name(name) do
    case String.split(name, " ", trim: true) do
      [first_name | [_ | _] = rest] ->
        {first_name, List.last(rest)}

      [first_name] ->
        {first_name, nil}
    end
  end

  def fcm_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:fcm_token])
    |> validate_required([:fcm_token])
  end

  def invite_user_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :password,
      :time_zone,
      :onboarding_flow_source,
      :organization_id
    ])
    |> validate_email_format()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          email: String.t(),
          hashed_password: String.t(),
          sign_up_auth_provider: atom(),
          stripe_customer_id: String.t(),
          time_zone: String.t(),
          confirmed_at: DateTime.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t(),
          onboarding: Todoplace.Onboardings.Onboarding.t()
        }
end
