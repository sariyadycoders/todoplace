defmodule TodoplaceWeb.LiveOrganization do
  use TodoplaceWeb, :live_view

  @impl true
  def mount(_params, %{"organization_id" => organization_id}, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="organization-content">
      <%!-- <h1><%= @organization.name %></h1> --%>
      <%!-- <p><%= @organization.description %></p> --%>
    </div>
    """
  end
end
