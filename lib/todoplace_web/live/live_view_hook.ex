defmodule TodoplaceWeb.LiveViewHook do
  use Phoenix.LiveView
  alias Phoenix.LiveView.JS

  def mount(_params, %{"user_id" => user_id}, socket) do
    socket = assign(socket, :user_id, user_id)
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id="fcm-hook" phx-hook="FCMTokenHook" data-user-id={@user_id}></div>
    """
  end
end
