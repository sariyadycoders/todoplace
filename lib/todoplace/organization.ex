defmodule Todoplace.Organization do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Todoplace.{
    PackagePaymentPreset,
    OrganizationJobType,
    OrganizationCard,
    Package,
    Utils,
    Campaign,
    Client,
    Accounts.User,
    Repo,
    Profiles.Profile,
    GlobalSettings.GalleryProduct,
    Address,
    PreferredFilter,
    Accounts.UserInvitation,
    TenantManager
  }

  alias Todoplace.Organization
  alias Todoplace.UserOrganization

  defmodule EmailSignature do
    @moduledoc false
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:show_phone, :boolean, default: true)
      field(:show_business_name, :boolean, default: true)
      field(:content, :string)
    end

    def changeset(signature, attrs) do
      signature
      |> cast(attrs, [:show_phone, :show_business_name, :content])
    end
  end

  defmodule PaymentOptions do
    @moduledoc false
    use Ecto.Schema
    @primary_key false

    embedded_schema do
      field(:allow_cash, :boolean, default: false)
      field(:allow_affirm, :boolean, default: false)
      field(:allow_afterpay_clearpay, :boolean, default: false)
      field(:allow_klarna, :boolean, default: false)
      field(:allow_cashapp, :boolean, default: false)
    end

    def changeset(payment_options, attrs) do
      payment_options
      |> cast(attrs, [
        :allow_cash,
        :allow_affirm,
        :allow_afterpay_clearpay,
        :allow_klarna,
        :allow_cashapp
      ])
    end
  end

  defmodule ClientProposal do
    @moduledoc false
    use Ecto.Schema
    @primary_key false

    embedded_schema do
      field(:title, :string)
      field(:booking_panel_title, :string)
      field(:message, :string)
      field(:contact_button, :string)
    end

    def changeset(proposal, attrs) do
      proposal
      |> cast(attrs, [:title, :booking_panel_title, :message, :contact_button])
      |> validate_required([:title, :booking_panel_title, :message, :contact_button],
        message: "should not be empty"
      )
      |> validate_field(:title, min: 5, max: 100)
      |> validate_field(:booking_panel_title, min: 10, max: 100)
      |> validate_field(:contact_button, min: 5, max: 100)
    end

    defp validate_field(changeset, field, min: min, max: max) do
      check_field = get_field(changeset, field)

      cond do
        String.length(check_field) < min ->
          add_error(changeset, field, "must be greater than #{min} characters")

        String.length(check_field) > max ->
          add_error(changeset, field, "must be less than #{max} characters")

        !Regex.match?(~r/[A-Za-z]/, check_field) ->
          add_error(changeset, field, "has invalide format")

        true ->
          changeset
      end
    end
  end

  schema "organizations" do
    field(:name, :string)
    field(:stripe_account_id, :string)
    field(:slug, :string)
    field(:previous_slug, :string)
    field(:is_active, :boolean, default: true)
    field(:global_automation_enabled, :boolean, default: true)
    embeds_one(:profile, Profile, on_replace: :update)
    embeds_one(:email_signature, EmailSignature, on_replace: :update)
    embeds_one(:payment_options, PaymentOptions, on_replace: :update)
    embeds_one(:client_proposal, ClientProposal, on_replace: :update)

    has_many(:package_templates, Package, where: [package_template_id: nil])
    has_many(:campaigns, Campaign)
    has_many(:package_payment_presets, PackagePaymentPreset)
    has_many(:brand_links, Todoplace.BrandLink)
    has_many(:clients, Client)
    has_many(:organization_cards, OrganizationCard)
    has_many(:gs_gallery_products, GalleryProduct)
    has_many(:organization_job_types, OrganizationJobType, on_replace: :delete)
    has_many(:invited_organization, UserInvitation)

    has_one(:global_setting, Todoplace.GlobalSettings.Gallery)
    has_one(:user, User)
    has_one(:address, Address, on_replace: :update)
    has_one(:preferred_filters, PreferredFilter, on_replace: :update)
    has_many(:organization_users, Todoplace.UserOrganization)
    # many_to_many :users, Todoplace.Accounts.User, join_through: "users_organizations"

    timestamps()
  end

  @type t :: %__MODULE__{name: String.t()}

  def email_signature_changeset(organization, attrs) do
    organization
    |> cast(attrs, [])
    |> cast_embed(:email_signature)
  end

  def client_proposal_portal_changeset(organization, attrs) do
    organization
    |> cast(attrs, [])
    |> cast_embed(:client_proposal)
  end

  def address_changeset(organization, attrs) do
    organization
    |> cast(attrs, [])
    |> cast_assoc(:address, required: true)
  end

  def registration_changeset(organization, attrs, "" <> user_name),
    do:
      registration_changeset(
        organization,
        Map.put_new(
          attrs,
          :name,
          build_organization_name("#{user_name} Org")
          |> Utils.capitalize_all_words()
        )
      )

  def registration_changeset(organization, attrs, _user_name),
    do: registration_changeset(organization, attrs)

  def registration_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug])
    |> cast_assoc(:organization_cards, with: &OrganizationCard.changeset/2)
    |> cast_assoc(:gs_gallery_products, with: &GalleryProduct.changeset/2)
    |> cast_assoc(:organization_job_types, with: &OrganizationJobType.changeset/2)
    |> validate_required([:name])
    |> validate_org_name()
    |> then(fn changeset ->
      case get_change(changeset, :slug) do
        nil ->
          change_slug(changeset)

        _ ->
          changeset
      end
    end)
    |> unique_constraint(:slug)
  end

  defp validate_org_name(changeset) do
    name = get_change(changeset, :name)

    if name && check_existing_name_and_slug(name, build_slug(name)) do
      add_error(
        changeset,
        :name,
        "Business name already exists. Please try with a different name."
      )
    else
      changeset
    end
  end

  def active_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:is_active])
    |> validate_required([:name])
  end

  def name_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> prepare_changes(&change_slug/1)
    |> validate_org_name()
    |> unique_constraint(:slug)
    |> case do
      %{changes: %{name: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :name, "")
    end
  end

  def edit_profile_changeset(organization, attrs) do
    organization
    |> cast(attrs, [])
    |> cast_embed(:profile)
  end

  def payment_options_changeset(organization, attrs) do
    organization
    |> cast(attrs, [])
    |> cast_embed(:payment_options)
  end

  def assign_stripe_account_changeset(%__MODULE__{} = organization, "" <> stripe_account_id),
    do: organization |> change(stripe_account_id: stripe_account_id)

  defp build_organization_name(name) do
    name
    |> reformat_string()
    |> find_unique_organization_name()
  end

  @spec find_unique_organization_name(name :: String.t(), count :: integer) :: String.t()
  defp find_unique_organization_name(name, count \\ 0) do
    updated_name =
      if count > 0 do
        "#{name} #{count}"
      else
        name
      end

    updated_slug = build_slug(updated_name)

    if check_existing_name_and_slug(updated_name, updated_slug) do
      find_unique_organization_name(name, count + 1)
    else
      updated_name
    end
  end

  def create_organization(params, user_id) do
    %Organization{}
    |> registration_changeset(params)
    |> cast_embed(:profile)
    |> Repo.insert()
    |> case do
      {:ok, organization} ->
        # Create tenant schema for the organization
        tenant_schema_result = TenantManager.create_tenant_schema(organization.slug)

        case tenant_schema_result do
          {:ok, _message} ->
            #     # Insert the user-organization association after schema creation
            insert_user_organization_association(organization.id, user_id)
            {:ok, organization}

          {:error, reason} ->
            # Handle schema creation failure, e.g., by rolling back organization creation
            Repo.rollback("Failed to create tenant schema: #{inspect(reason)}")
        end

      {:error, changeset} = error ->
        error
    end
  end

  def insert_user_organization_association(organization_id, user_id) do
    %{user_id: user_id, organization_id: organization_id, role: "admin", status: "Joined"}
    |> Todoplace.Accounts.create_user_organization()

    handle_notifications(user_id, organization_id)
  end

  def build_slug(nil), do: nil

  def build_slug(name), do: reformat_string(name, "-")

  @spec check_existing_name_and_slug(name :: String.t(), slug :: String.t()) :: boolean
  defp check_existing_name_and_slug(name, slug) do
    Repo.exists?(
      from o in __MODULE__,
        where:
          fragment(
            "LOWER(?) = LOWER(?) OR LOWER(?) = LOWER(?)",
            o.name,
            ^name,
            o.slug,
            ^slug
          ),
        limit: 1
    )
  end

  def handle_notifications(user_id, organization_id) do
    payload = %{
      title: "Hello!",
      body: "You have a new message.",
      icon: ""
    }

    Todoplace.Accounts.Notification.send_notification(user_id, organization_id, payload)
  end

  def list_organizations(user_id) do
    from(o in Organization,
      join: uo in "users_organizations",
      on: o.id == uo.organization_id,
      where: uo.user_id == ^user_id
    )
    |> Repo.all()
  end

  def list_organizations_active(user_id) do
    from(o in Organization,
      join: uo in "users_organizations",
      on: o.id == uo.organization_id,
      # Use a string literal
      where:
        uo.user_id == ^user_id and
          uo.org_status == "active"
    )
    |> Repo.all()
  end

  def get_org_status(user_id, organization_id) do
    from(uo in Todoplace.UserOrganization,
      where: uo.user_id == ^user_id and uo.organization_id == ^organization_id,
      select: uo.org_status
    )
    |> Todoplace.Repo.one()
  end

  @spec toggle_org_status(integer(), integer()) :: {:ok, %UserOrganization{}} | {:error, term()}
  def toggle_org_status(user_id, organization_id) do
    # Find the specific record where both user_id and organization_id match
    query =
      from(u in UserOrganization,
        where: u.user_id == ^user_id and u.organization_id == ^organization_id,
        # Limit to 1 record since we're updating a single entry
        limit: 1
      )

    case Repo.one(query) do
      # No record found
      nil ->
        {:error, :not_found}

      user_organization ->
        new_status = toggle_status(user_organization.org_status)
        # Create changeset and update the record
        Repo.update_all(
          from(u in UserOrganization,
            where: u.user_id == ^user_id and u.organization_id == ^organization_id
          ),
          set: [org_status: new_status]
        )

        {:ok, %{user_organization | org_status: new_status}}
    end
  end

  defp toggle_status(:active), do: :inactive
  defp toggle_status(:inactive), do: :active
  # Handle unexpected statuses, if needed
  defp toggle_status(status), do: status

  @spec reformat_string(name :: String.t(), replace_by :: String.t()) :: String.t()
  defp reformat_string(name, replace_by \\ " "),
    do:
      name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, replace_by) |> String.trim("-")

  defp change_slug(changeset),
    do:
      changeset
      |> put_change(:previous_slug, get_field(changeset, :slug))
      |> put_change(:slug, changeset |> get_field(:name) |> build_slug())
end

# global_automation_enabled default true

# when turns off
# disable all automation emails for this organization
# -> for manuall trigger emails confirm case when all emails diabsle how they works
# -> if no email found then fetch default email where org_id nil
# stopped all active emails with condition :gloabally_stopped
# when turns on
# enable all disabled emails for this organization
# revert all those emails which have gloabally_stopped
