defmodule TodoplaceWeb.Live.EventWrapper do
  defmacro __using__(_) do
    quote do
      import TodoplaceWeb.Live.EventWrapper

      @impl true
      def handle_event(event, params, socket) do
        try do
          handle_event(event, params, socket)
        rescue
          e ->
            handle_event_error(event, e, socket)
        end
      end

      defoverridable handle_event: 3

      defp handle_event_error(event, error, socket) do
        Todoplace.Cache.refresh_current_user_cache(socket.assigns.current_user_data.session_token)
        Logger.error("Error handling event #{event}: #{Exception.message(error)}")
        {:noreply, socket}
      end
    end
  end
end
