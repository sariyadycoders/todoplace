defmodule Todoplace.Profiles do
  @moduledoc "context module for public photographer profile"
  use TodoplaceWeb, :verified_routes

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Todoplace.{
    Repo,
    BrandLink,
    Organization,
    Job,
    JobType,
    ClientMessage,
    Client,
    Accounts.User,
    Notifiers.UserNotifier,
    EmailAutomations,
    EmailAutomation.EmailSchedule,
    EmailAutomationSchedules
  }

  require Logger

  defmodule ProfileImage do
    @moduledoc "a public image embedded in the profile json"
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field(:url, :string)
      field(:content_type, :string)
    end

    def changeset(profile_image, attrs) do
      cast(profile_image, attrs, [:id, :url, :content_type])
    end
  end

  defmodule Profile do
    @moduledoc "used to render the organization public profile"
    use Ecto.Schema
    import Ecto.Changeset

    @colors ~w(#5C6578 #312B3F #865678 #93B6D6 #A98C77 #ECABAE #9E5D5D #6E967E)
    @default_color hd(@colors)

    def colors(), do: @colors

    def default_color(), do: @default_color

    @primary_key false
    embedded_schema do
      field(:is_enabled, :boolean, default: true)
      field(:color, :string)
      field(:description, :string)
      field(:job_types, {:array, :string})
      field(:job_types_description, :string)

      embeds_one(:logo, ProfileImage, on_replace: :update)
      embeds_one(:main_image, ProfileImage, on_replace: :update)
    end

    def enabled?(%__MODULE__{is_enabled: is_enabled}), do: is_enabled

    @fields ~w[color description job_types_description]a
    def changeset(%__MODULE__{} = profile, attrs) do
      profile
      |> cast(attrs, @fields)
      |> cast_embed(:logo)
      |> cast_embed(:main_image)
    end

    def changeset_for_factory_reset(%__MODULE__{} = profile, attrs) do
      cast(profile, attrs, [:job_types | @fields])
    end

    def url_validation_errors(url) do
      case URI.parse(url) do
        %{scheme: nil} ->
          ["is invalid"]

        %{scheme: scheme, host: "" <> host} when scheme in ["http", "https"] ->
          label = "[a-zA-Z0-9\\-]{1,63}+"

          if "^(?:(?:#{label})\\.)+(?:#{label})$"
             |> Regex.compile!()
             |> Regex.match?(host),
             do: [],
             else: ["is invalid"]

        %{scheme: _scheme} ->
          ["is invalid"]
      end
    end
  end

  defmodule Contact do
    @moduledoc "container for the contact form data"
    use Ecto.Schema
    import Ecto.Changeset
    import Todoplace.Accounts.User, only: [validate_email_format: 1]
    import TodoplaceWeb.Gettext

    @fields ~w[name email phone referred_by referral_name job_type message]a
    @required_fields ~w[name email phone job_type message]a

    embedded_schema do
      for field <- @fields do
        field(field, :string)
      end
    end

    def changeset(%__MODULE__{} = contact, attrs) do
      contact
      |> cast(attrs, @fields)
      |> validate_email_format()
      |> validate_required(@required_fields)
    end

    def message_for(%__MODULE__{} = contact) do
      msg = """
        name: #{contact.name}
        email: #{contact.email}
        phone: #{contact.phone}
      """

      build_message(contact, msg) <>
        """
          job type: #{dyn_gettext(contact.job_type)}
          message: #{contact.message}
        """
    end

    defp build_message(%{referred_by: nil}, msg), do: msg

    defp build_message(%{referral_name: nil, referred_by: ref_by}, msg),
      do: msg <> referred_by(ref_by)

    defp build_message(%{referral_name: ref_name, referred_by: ref_by}, msg),
      do: msg <> referred_by(ref_by) <> referral_name(ref_name)

    defp referred_by(nil), do: nil
    defp referred_by(value), do: "referred by: #{value}"

    defp referral_name(nil), do: nil
    defp referral_name(value), do: "referral name: #{value}"
  end

  def contact_changeset(contact, attrs) do
    Contact.changeset(contact, attrs)
  end

  def contact_changeset(attrs) do
    Contact.changeset(%Contact{}, attrs)
  end

  def contact_changeset() do
    Contact.changeset(%Contact{}, %{})
  end

  defp brand_link_profile_changeset(organization, %{"brand_links" => _}) do
    organization
    |> cast_assoc(:brand_links,
      required: true,
      with: &BrandLink.brand_link_changeset(&1, &2)
    )
  end

  defp brand_link_profile_changeset(organization, _), do: organization

  def edit_organization_profile_changeset(%Organization{} = organization, attrs) do
    organization
    |> Organization.edit_profile_changeset(attrs)
    |> brand_link_profile_changeset(attrs)
  end

  def update_organization_profile(%Organization{} = organization, attrs) do
    organization
    |> edit_organization_profile_changeset(attrs)
    |> Repo.update()
  end

  def handle_contact(%{id: organization_id} = _organization, params, helpers) do
    changeset = contact_changeset(params)

    case changeset do
      %{valid?: true} ->
        contact = Ecto.Changeset.apply_changes(changeset)

        {:ok, _} =
          Ecto.Multi.new()
          |> Ecto.Multi.insert(
            :client,
            contact
            |> Map.take([:name, :email, :phone, :referred_by, :referral_name])
            |> Map.put(:organization_id, organization_id)
            |> Client.changeset(),
            on_conflict: {:replace, [:email, :archived_at]},
            conflict_target: [:organization_id, :email],
            returning: [:id]
          )
          |> Ecto.Multi.insert(
            :lead,
            &Job.changeset(%{type: contact.job_type, client_id: &1.client.id})
          )
          |> Ecto.Multi.insert_all(:email_automation_job, EmailSchedule, fn %{lead: job} ->
            job = job |> Repo.preload(client: [organization: [:user]])

            EmailAutomationSchedules.job_emails(
              job.type,
              job.client.organization.id,
              job.id,
              :lead,
              [:abandoned_emails]
            )
          end)
          |> Ecto.Multi.insert(
            :message,
            &ClientMessage.create_inbound_changeset(
              %{
                job_id: &1.lead.id,
                subject: "New lead from profile",
                body_text: Contact.message_for(contact)
              },
              [:job_id]
            )
          )
          |> Ecto.Multi.run(
            :email,
            fn _, changes ->
              UserNotifier.deliver_new_lead_email(changes.lead, contact.message, helpers)
              # Send immediately client contact Automations email

              EmailAutomations.send_schedule_email(changes.lead, :client_contact)
              {:ok, :email}
            end
          )
          |> Repo.transaction()

        {:ok, contact}

      _ ->
        {:error, Map.put(changeset, :action, :validate)}
    end
  end

  def find_organization_by_slug(slug: slug) do
    from(
      o in Organization,
      where: o.slug == ^slug or o.previous_slug == ^slug,
      order_by:
        fragment(
          """
          case
            when ?.slug = ? then 0
            when ?.previous_slug = ? then 1
          end asc
          """,
          o,
          ^slug,
          o,
          ^slug
        ),
      limit: 1,
      preload: [:user, :organization_job_types]
    )
    |> Repo.one!()
    |> Repo.preload(brand_links: from(bl in BrandLink, where: bl.link_id == "website"))
  end

  def find_organization_by(slug: slug) do
    from(
      o in Organization,
      where:
        (o.slug == ^slug or o.previous_slug == ^slug) and
          fragment("coalesce((profile -> 'is_enabled')::boolean, true)"),
      order_by:
        fragment(
          """
          case
            when ?.slug = ? then 0
            when ?.previous_slug = ? then 1
          end asc
          """,
          o,
          ^slug,
          o,
          ^slug
        ),
      limit: 1,
      preload: [:user, :organization_job_types]
    )
    |> Repo.one!()
    |> Repo.preload(brand_links: from(bl in BrandLink, where: bl.link_id == "website"))
  end

  def find_organization_by(user: %User{} = user) do
    user
    |> Repo.preload(organization: :user)
    |> Map.get(:organization)
    |> Repo.preload([
      :organization_job_types,
      brand_links: from(bl in BrandLink, where: bl.link_id == "website")
    ])
  end

  def get_brand_links_by_organization(organization),
    do: Repo.preload(organization, :brand_links, force: true) |> Map.get(:brand_links)

  def enabled?(%Organization{profile: profile}), do: Profile.enabled?(profile)

  def toggle(%Organization{} = organization) do
    organization
    |> Ecto.Changeset.change(%{profile: %{is_enabled: !enabled?(organization)}})
    |> Repo.update!()
  end

  defdelegate colors(), to: Profile
  defdelegate job_types(), to: JobType, as: :all

  def color(%Organization{profile: %{color: color}}), do: color
  def color(_), do: Profile.default_color()

  def public_url(%Organization{slug: slug}) do
    url(~p"/photographer/#{slug}")
  end

  def embed_url(%Organization{slug: slug}) do
    url(~p"/photographer/embed/#{slug}")
  end

  def embed_code(%Organization{} = organization) do
    ~s(<iframe src="#{embed_url(organization)}" frameborder="0" style="max-width:100%;width:100%;height:100%;min-height:700px;"></iframe>)
  end

  def subscribe_to_photo_processed(%{slug: slug}) do
    topic = "profile_photo_ready:#{slug}"

    Phoenix.PubSub.subscribe(Todoplace.PubSub, topic)
  end

  def handle_photo_processed_message(path, id) do
    image_field = if String.contains?(path, "main_image"), do: "main_image", else: "logo"

    image_field_atom = String.to_atom(image_field)

    from(org in Organization, where: fragment("profile -> ? ->> 'id' = ? ", ^image_field, ^id))
    |> Repo.all()
    |> case do
      [%{profile: profile} = organization] ->
        url = %URI{host: static_host(), path: "/" <> path, scheme: "https"} |> URI.to_string()

        {:ok, organization} =
          update_organization_profile(organization, %{
            profile: %{image_field_atom => %{url: url}}
          })

        topic = "profile_photo_ready:#{organization.slug}"

        Phoenix.PubSub.broadcast(
          Todoplace.PubSub,
          topic,
          {:image_ready, image_field_atom, organization}
        )

        with %{^image_field_atom => %{url: "" <> old_url}} <- profile do
          delete_image_from_storage(old_url)
        end

      _ ->
        Logger.warning("ignoring path #{path} for version #{id}")
    end

    :ok
  end

  def remove_photo(organization, image_field) do
    image_url = Map.get(organization.profile, image_field).url

    {:ok, organization} =
      update_organization_profile(organization, %{
        profile: %{image_field => nil}
      })

    delete_image_from_storage(image_url)

    organization
  end

  def preflight(%{upload_config: image_field} = image, organization) do
    resize_height =
      %{
        logo: 104,
        main_image: 600
      }
      |> Map.get(image_field)

    params =
      Todoplace.Galleries.Workers.PhotoStorage.params_for_upload(
        expires_in: 600,
        bucket: bucket(),
        key: to_filename(organization, image, remove_file_extension(image.client_name)),
        fields:
          %{
            "resize" => Jason.encode!(%{height: resize_height, withoutEnlargement: true}),
            "pubsub-topic" => output_topic(),
            "version-id" => image.uuid,
            "out-filename" => to_filename(organization, image, "#{image.uuid}.png", ["resized"])
          }
          |> meta_fields()
          |> Enum.into(%{
            "content-type" => image.client_type,
            "cache-control" => "public, max-age=@upload_options"
          }),
        conditions: [
          [
            "content-length-range",
            0,
            String.to_integer(Application.get_env(:todoplace, :photo_max_file_size))
          ]
        ]
      )

    {:ok, organization} =
      update_organization_profile(organization, %{
        profile: %{image_field => %{id: image.uuid, content_type: image.client_type}}
      })

    {:ok, make_meta(params), organization}
  end

  def brand_logo_preflight(%{upload_config: image_field} = image, organization) do
    resize_height =
      %{
        logo: 104,
        main_image: 600
      }
      |> Map.get(image_field)

    {:ok,
     Todoplace.Galleries.Workers.PhotoStorage.params_for_upload(
       expires_in: 600,
       bucket: bucket(),
       key: to_filename(organization, image, remove_file_extension(image.client_name)),
       fields:
         %{
           "resize" => Jason.encode!(%{height: resize_height, withoutEnlargement: true}),
           "pubsub-topic" => output_topic(),
           "version-id" => image.uuid,
           "out-filename" => to_filename(organization, image, "#{image.uuid}.png")
         }
         |> meta_fields()
         |> Enum.into(%{
           "content-type" => image.client_type,
           "cache-control" => "public, max-age=@upload_options"
         }),
       conditions: [
         [
           "content-length-range",
           0,
           String.to_integer(Application.get_env(:todoplace, :photo_max_file_size))
         ]
       ]
     )
     |> make_meta()}
  end

  def logo_url(organization) do
    case organization do
      %{profile: %{logo: %{url: "" <> url}}} -> url
      _ -> nil
    end
  end

  def get_active_organization_job_types(organization_job_types) do
    organization_job_types
    |> Enum.filter(fn job_type -> job_type.show_on_business? end)
    |> Enum.sort_by(& &1.jobtype.position)
  end

  def get_public_organization_job_types(organization_job_types) do
    organization_job_types
    |> Enum.filter(fn job_type -> job_type.show_on_profile? end)
    |> Enum.sort_by(& &1.jobtype.position)
  end

  def enabled_job_types(organization_job_types) do
    Repo.preload(organization_job_types, [:jobtype])
    |> get_active_organization_job_types()
    |> Enum.map(& &1.job_type)
  end

  def public_job_types(organization_job_types) do
    Repo.preload(organization_job_types, [:jobtype])
    |> get_public_organization_job_types()
    |> Enum.map(& &1.job_type)
  end

  defp delete_image_from_storage(url) do
    Task.start(fn ->
      url
      |> URI.parse()
      |> Map.get(:path)
      |> Path.split()
      |> Enum.drop(2)
      |> Path.join()
      |> Todoplace.Galleries.Workers.PhotoStorage.delete(bucket())
    end)
  end

  defp remove_file_extension(filename) do
    String.replace(filename, [".svg", ".png", ".jpeg", ".jpg", ".pdf", ".docx", ".txt"], "")
  end

  defp make_meta(params) do
    params |> Map.take([:url, :key, :fields]) |> Map.put(:uploader, "GCS")
  end

  defp to_filename(organization, %{client_type: content_type} = image, name),
    do:
      to_filename(
        organization,
        image,
        Enum.join([name, content_type |> MIME.extensions() |> hd], "."),
        []
      )

  defp to_filename(
         %{slug: nil},
         %{
           upload_config: upload_type
         },
         name,
         subdir
       ),
       do:
         [["creating_organization", Atom.to_string(upload_type)], subdir, [name]]
         |> Enum.concat()
         |> Path.join()

  defp to_filename(
         %{slug: slug},
         %{
           upload_config: upload_type
         },
         name,
         subdir
       ),
       do:
         [[slug, Atom.to_string(upload_type)], subdir, [name]]
         |> Enum.concat()
         |> Path.join()

  defp meta_fields(fields),
    do:
      for(
        {key, value} <- fields,
        into: %{},
        do: {Enum.join(["x-goog-meta", key], "-"), value}
      )

  defp output_topic, do: Application.get_env(:todoplace, :photo_processing_output_topic)

  defp bucket, do: Keyword.get(config(), :bucket)

  defp static_host, do: Keyword.get(config(), :static_host)

  defp config(), do: Application.get_env(:todoplace, :profile_images)
end
