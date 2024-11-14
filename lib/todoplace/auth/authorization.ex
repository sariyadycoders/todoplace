defmodule Todoplace.Auth.Authorization do
  @moduledoc """
  Module for handling authorization in LiveViews.
  """

  alias Todoplace.Roles.RoleAction
  alias Todoplace.Accounts.User
  import Ecto.Query

  defmacro __using__(_opts) do
    quote do
      import TodoplaceWeb.Authorization
    end
  end

  defmacro authorize_action(action, handler: handler) do
    quote do
      def handle_event(unquote(action), params, socket) do
        TodoplaceWeb.Authorization.handle_authorization(
          unquote(action),
          params,
          socket,
          __MODULE__,
          unquote(handler)
        )
      end
    end
  end

  def handle_authorization(action, params, socket, module, handler) do
    if user_has_permission?(socket.assigns.current_user.role, action) do
      # Use the `handler` dynamically
      case handler do
        fun when is_function(fun, 2) ->
          fun.(params, socket)
        atom when is_atom(atom) ->
          apply(module, atom, [params, socket])
        _ ->
          raise ArgumentError, "Handler must be an atom or a function reference"
      end
    else
      {:noreply, socket}
    end
  end

  def user_has_permission?(role, action) do
    with %RoleAction{} = role_action <- Todoplace.Accounts.fetch_role_action(role, action) do
      # Return true if role_action exists
      true
    else
      _ -> false
    end
  end

  def apply_data_restriction(query, %User{role: role} = user) do
    case get_data_scope_for_role(role) do
      "all" -> query
      "own" -> apply_own_scope(query, user)
      _ -> exclude_results(query)
    end
  end

  defp get_data_scope_for_role(role) do
    # This is just an example, you should fetch this dynamically
    case role do
      "admin" -> "all"
      "user" -> "own"
      _ -> "none"
    end
  end

  defp apply_own_scope(query, %User{id: user_id}) do
    from(q in query, where: q.user_id == ^user_id)
  end

  defp exclude_results(query) do
    from(q in query, where: false) # This will return no results
  end
end
