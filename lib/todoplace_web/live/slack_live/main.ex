defmodule TodoplaceWeb.MainLive do
  use TodoplaceWeb, live_view: [layout: "main"]
  use TodoplaceWeb.Live.OrganizationLayoutHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- <%= render_layout({TodoplaceWeb.LayoutView, "slack_live_layout.html"}, assigns) do %> --%>
    <%!-- <%= live_render(@socket, TodoplaceWeb.WorkspaceLiveView, id: @current_workspace.id, session: %{"organization_id" => @current_workspace.id}) %> --%>
    <%!-- <% end %> --%>
    """
  end
end
