defmodule Todoplace.Onboardings do
  @moduledoc "context module for photographer onboarding"
  alias Todoplace.{
    Repo,
    Accounts.User,
    Organization,
    OrganizationJobType,
    Profiles.Profile,
    Utils,
    Subscriptions
  }

  import Ecto.Changeset
  import Todoplace.Accounts.User, only: [put_new_attr: 3, update_attr_in: 3]
  import Ecto.Query, only: [from: 2]

  @non_us_state "Non-US"

  defmodule Onboarding do
    @moduledoc "Container for user specific onboarding info. Embedded in users table."

    use Ecto.Schema

    defmodule IntroState do
      @moduledoc "Container for user specific introjs state. Embedded in onboarding embed."
      use Ecto.Schema

      embedded_schema do
        field(:changed_at, :utc_datetime)
        field(:state, Ecto.Enum, values: [:completed, :dismissed, :restarted])
      end

      @type t :: %__MODULE__{
              changed_at: DateTime.t(),
              state: atom()
            }
    end

    @software_options [
      sprout_studio: "Sprout Studio",
      pixieset: "Pixieset",
      shootproof: "Shootproof",
      honeybook: "Honeybook",
      session: "Session",
      other: "Other",
      none: "None"
    ]

    @primary_key false
    embedded_schema do
      field(:phone, :string)

      field(:switching_from_softwares, {:array, Ecto.Enum},
        values: Keyword.keys(@software_options)
      )

      field(:completed_at, :utc_datetime)
      field(:zipcode, :string)
      field(:country, :string)
      field(:interested_in, :string)
      field(:welcome_count, :integer)
      field(:sidebar_open_preference, :boolean, default: true)
      field(:promotion_code, :string, default: nil)
      embeds_many(:intro_states, IntroState, on_replace: :delete)

      @type t :: %__MODULE__{
              phone: String.t(),
              switching_from_softwares: [atom()],
              completed_at: DateTime.t(),
              zipcode: String.t(),
              country: String.t(),
              interested_in: String.t(),
              welcome_count: integer(),
              sidebar_open_preference: boolean(),
              promotion_code: String.t(),
              intro_states: [IntroState.t()]
            }
    end

    def changeset(%__MODULE__{} = onboarding, attrs) do
      onboarding
      |> cast(attrs, [
        :phone,
        :switching_from_softwares,
        :zipcode,
        :country,
        :interested_in,
        :welcome_count,
        :promotion_code
      ])
      |> validate_required([:country, :interested_in, :zipcode])
      |> validate_change(:promotion_code, &valid_promotion_codes/2)
    end

    def phone_changeset(%__MODULE__{} = onboarding, attrs) do
      onboarding
      |> cast(attrs, [:phone])
      |> Utils.validate_phone(:phone)
    end

    def promotion_code_changeset(%__MODULE__{} = onboarding, attrs) do
      onboarding
      |> cast(attrs, [:promotion_code])
      |> validate_change(:promotion_code, &valid_promotion_codes/2)
    end

    def sidebar_preference_changeset(%__MODULE__{} = onboarding, attrs) do
      onboarding
      |> cast(attrs, [:sidebar_open_preference])
    end

    def welcome_count_changeset(%__MODULE__{} = onboarding, attrs) do
      onboarding
      |> cast(attrs, [:welcome_count])
      |> validate_required([:welcome_count])
    end

    def completed?(%__MODULE__{completed_at: nil}), do: false
    def completed?(%__MODULE__{}), do: true

    def software_options(), do: @software_options

    defp valid_promotion_codes(field, value) do
      if is_nil(Subscriptions.maybe_get_promotion_code?(value)) do
        [{field, "(code doesn't exist)"}]
      else
        []
      end
    end
  end

  defmodule MetaData do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:purpose, :string)
      field(:role, :string)
      field(:team_size, :string)
      field(:company_size, :string)
      field(:first_focus, :string)
      field(:first_manage, :string)


    end

    def changeset(%__MODULE__{} = data, attrs) do
      data
      |> cast(attrs, [
        :purpose,
        :role,
        :team_size,
        :company_size,
        :first_focus,
        :first_manage
      ])
    end
  end

  defdelegate software_options(), to: Onboarding

  def changeset(%User{} = user, attrs, opts \\ []) do
    step = Keyword.get(opts, :step, 3)
    onboarding_type = Keyword.get(opts, :onboarding_type, nil)

    user
    |> cast(
      attrs
      |> put_new_attr(:onboarding, %{})
      |> update_attr_in(
        [:organization],
        &((&1 || %{})
          |> put_new_attr(:profile, %{color: Profile.default_color()})
          |> put_new_attr(:id, user.organization_id))
      ),
      []
    )
    |> cast_embed(:onboarding, with: &onboarding_changeset(&1, &2, step), required: true)
    |> cast_embed(:metadata, with: &data_changeset(&1, &2, step), required: true)
    |> cast_assoc(:organization,
      with: &organization_onboarding_changeset(&1, &2, step, onboarding_type),
      required: true
    )
  end

  def state_options(),
    do:
      from(adjustment in Todoplace.Packages.CostOfLivingAdjustment,
        select: adjustment.state,
        order_by: [
          desc: fragment("case when ? = ? then 1 else 0 end", adjustment.state, @non_us_state),
          asc: adjustment.state
        ]
      )
      |> Repo.all()
      |> Enum.map(&{&1, &1})

  def non_us_state(), do: @non_us_state

  def non_us_state?(%User{onboarding: %{state: state}}), do: non_us_state?(state)
  def non_us_state?(state), do: state == @non_us_state

  def complete!(user),
    do:
      user
      |> tap(&Todoplace.Packages.create_initial/1)
      |> User.complete_onboarding_changeset()
      |> Repo.update!()

  def save_intro_state(current_user, intro_id, state) do
    new_intro_state = %Onboarding.IntroState{
      changed_at: DateTime.utc_now(),
      state: state,
      id: intro_id
    }

    update_intro_state(
      current_user,
      fn %{intro_states: intro_states} = onboarding, _ ->
        onboarding
        |> change()
        |> put_embed(:intro_states, [
          new_intro_state | Enum.filter(intro_states, &(&1.id != intro_id))
        ])
      end
    )
  end

  def restart_intro_state(current_user) do
    update_intro_state(
      current_user,
      fn %{intro_states: intro_states} = onboarding, _ ->
        onboarding
        |> change()
        |> put_embed(
          :intro_states,
          Enum.map(intro_states, fn state ->
            Ecto.Changeset.change(state, %{state: :restarted})
          end)
        )
      end
    )
  end

  def user_onboarding_phone_changeset(current_user, attr) do
    current_user
    |> cast(attr, [])
    |> cast_embed(:onboarding, with: &Onboarding.phone_changeset(&1, &2), required: true)
    |> case do
      %{changes: %{onboarding: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :phone, "did not change")
    end
  end

  def user_update_promotion_code_changeset(current_user, attrs) do
    current_user
    |> cast(attrs, [])
    |> cast_embed(:onboarding, with: &Onboarding.promotion_code_changeset(&1, &2))
  end

  def user_update_sidebar_preference_changeset(current_user, attrs) do
    current_user
    |> cast(attrs, [])
    |> cast_embed(:onboarding, with: &Onboarding.sidebar_preference_changeset(&1, &2))
  end

  def increase_welcome_count!(%{onboarding: %{welcome_count: count}} = current_user) do
    current_user
    |> cast(%{onboarding: %{welcome_count: (count || 0) + 1}}, [])
    |> cast_embed(:onboarding, with: &Onboarding.welcome_count_changeset/2, required: true)
    |> Repo.update!()
  end

  def show_intro?(current_user, intro_id) do
    for(
      %{id: ^intro_id, state: state} when state in [:completed, :dismissed] <-
        current_user.onboarding.intro_states,
      reduce: true
    ) do
      _ -> false
    end
  end

  defp update_intro_state(current_user, embed) do
    current_user
    |> cast(%{onboarding: %{}}, [])
    |> cast_embed(:onboarding, with: embed)
    |> Repo.update!()
  end

  defp organization_onboarding_changeset(organization, attrs, step, onboarding_type) do
    is_required? =
      if is_nil(onboarding_type) do
        step > 2
      else
        step > 3
      end

    organization
    |> Organization.registration_changeset(attrs)
    |> cast_embed(:profile,
      required: is_required?,
      with: &profile_onboarding_changeset(&1, &2, step)
    )
    |> cast_assoc(:organization_job_types,
      required: is_required?,
      with: &job_types_changeset(&1, &2, step)
    )
  end

  defp job_types_changeset(job_types, attrs, step) when step in [2, 3, 4] do
    attrs =
      if attrs && Map.has_key?(attrs, "job_type"),
        do:
          Map.put(attrs, "show_on_business?", true)
          |> Map.replace("id", String.to_integer(attrs["id"])),
        else: attrs

    OrganizationJobType.changeset(job_types, attrs)
  end

  defp profile_onboarding_changeset(profile, attrs, 3) do
    profile
    |> Profile.changeset(attrs)
  end

  defp profile_onboarding_changeset(profile, attrs, step) when step in [2, 3, 4] do
    profile
    |> profile_onboarding_changeset(attrs, 3)
  end

  defp onboarding_changeset(onboarding, attrs, _) do
    Onboarding.changeset(onboarding, attrs)
  end

  defp data_changeset(data, attrs, _) do
    MetaData.changeset(data, attrs)
  end
end
