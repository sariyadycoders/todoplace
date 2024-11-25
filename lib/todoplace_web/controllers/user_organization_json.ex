defmodule TodoplaceWeb.UserOrganizationJSON do
  alias Todoplace.Accounts.User

  @doc """
  Renders a list of users.
  """
  def user_organization(%{organizations: organizations}) do
    %{data: for(organization <- organizations, do: data(organization))}
  end

  defp data(%Todoplace.Organization{} = organization) do
    %{
      id: organization.id,
      name: organization.name,
      slug: organization.slug
    }
  end

  @doc """
  Renders a single user.
  """
  def show(%{user: user}) do
    %{data: data(user)}
  end

  defp data(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      active_organization_id: user.organization_id
    }
  end
end
