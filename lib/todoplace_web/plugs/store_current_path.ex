defmodule TodoplaceWeb.Plugs.StoreCurrentPath do
  import Plug.Conn

  def init(default), do: default

  def call(conn, _opts) do
    current_path = conn.request_path
    assign(conn, :current_path, current_path)
  end
end
