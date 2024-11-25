defmodule TodoplaceWeb.LeadContactIframeController do
  use TodoplaceWeb, :controller

  alias Todoplace.{Profiles}

  def index(conn, params) do
    conn
    |> assign_organization_by_slug(params)
    |> assign_preferred_phone_country()
    |> assign_changeset
    |> render("index.html")
  end

  def create(conn, %{"organization_slug" => organization_slug, "contact" => contact} = params) do
    organization = Profiles.find_organization_by_slug(slug: organization_slug)

    contact =
      organization.organization_job_types
      |> Profiles.public_job_types()
      |> assign_default_job_type(contact)

    case Profiles.handle_contact(organization, contact, TodoplaceWeb.Helpers) do
      {:ok, _client} ->
        conn
        |> render("thank-you.html")

      {:error, changeset} ->
        conn
        |> assign_organization_by_slug(params)
        |> assign_preferred_phone_country()
        |> assign(:changeset, changeset)
        |> put_flash(:error, "Form has errors")
        |> render("index.html")
    end
  end

  def create(conn, params) do
    conn
    |> assign_organization_by_slug(params)
    |> assign_preferred_phone_country()
    |> assign_changeset
    |> put_flash(:error, "Form is empty")
    |> render("index.html")
  end

  defp assign_organization_by_slug(conn, %{"organization_slug" => slug}) do
    organization = Profiles.find_organization_by_slug(slug: slug)

    conn
    |> assign(:job_types, Profiles.public_job_types(organization.organization_job_types))
    |> assign(:organization, organization)
  end

  defp assign_default_job_type(job_types, params) do
    if job_types == [],
      do: Map.put(params, "job_type", "global"),
      else: params
  end

  defp assign_changeset(conn) do
    conn
    |> assign(
      :changeset,
      Profiles.contact_changeset()
    )
  end

  defp assign_preferred_phone_country(
         %{assigns: %{organization: %{user: %{onboarding: %{country: "US"}}}}} = conn
       ) do
    assign(conn, :preferred_phone_country, default_preferred_phone_country())
  end

  defp assign_preferred_phone_country(
         %{assigns: %{organization: %{user: %{onboarding: %{country: "CA"}}}}} = conn
       ) do
    assign(
      conn,
      :preferred_phone_country,
      Enum.reverse(default_preferred_phone_country())
    )
  end

  defp assign_preferred_phone_country(
         %{assigns: %{organization: %{user: %{onboarding: %{country: country}}}}} = conn
       ) do
    if is_nil(country) do
      assign(conn, :preferred_phone_country, default_preferred_phone_country())
    else
      assign(conn, :preferred_phone_country, [country] ++ default_preferred_phone_country())
    end
  end

  defp assign_preferred_phone_country(conn) do
    assign(conn, :preferred_phone_country, default_preferred_phone_country())
  end

  defp default_preferred_phone_country(), do: ["US", "CA"]
end

defmodule TodoplaceWeb.LeadContactIframeHTML do
  use TodoplaceWeb, :html
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]
  import TodoplaceWeb.ViewHelpers

  embed_templates "templates/*"
end
