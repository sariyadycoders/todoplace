defmodule TodoplaceWeb.LiveViewHelpers do
  @moduledoc false
  import Phoenix.Component
  alias TodoplaceWeb.LiveAuth

  def assign_defaults(socket, session) do
    case LiveAuth.on_mount(:default, %{}, session, socket) do
      {:cont, socket} -> socket
      {:halt, socket} -> socket |> assign(:current_user, nil)
    end
  end
end
