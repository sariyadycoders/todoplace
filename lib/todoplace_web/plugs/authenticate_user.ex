# defmodule TodoplaceWeb.Plugs.AuthenticateUser do
#   import Plug.Conn
#   import Phoenix.Controller
#   alias TodoplaceWeb.Accounts

#   def init(opts), do: opts

#   def call(conn, _opts) do
#     with ["Bearer " <> token] <- get_req_header(conn, "Authorization"),
#          {:ok, user} <- decode_token(token) do
#       assign(conn, :current_user, user)
#     else
#       _ ->
#         conn
#         |> put_status(:unauthorized)
#         |> json(%{error: message})
#         |> halt()
#     end
#   end

#   defp decode_token(token) do
#     # TODO: Get user against token
#   end
# end
