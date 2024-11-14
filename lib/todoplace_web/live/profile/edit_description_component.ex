defmodule TodoplaceWeb.Live.Profile.EditDescriptionComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  import TodoplaceWeb.Shared.Quill, only: [quill_input: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal !max-w-md ">
      <h1 class="text-3xl font-bold">Edit Description</h1>

      <.form :let={f} for={@changeset} phx-change="validate" phx-submit="save" phx-target={@myself}>
        <%= for p <- inputs_for(f, :profile) do %>
          <.quill_input f={p} html_field={@field_name} placeholder="Start typing…" />
        <% end %>

        <TodoplaceWeb.LiveModal.footer />
      </.form>
    </div>
    """
  end

  @impl true
  defdelegate update(assigns, socket), to: TodoplaceWeb.Live.Profile.Shared

  @impl true
  defdelegate handle_event(name, params, socket), to: TodoplaceWeb.Live.Profile.Shared

  def open(socket, field_name) do
    socket
    |> assign(:field_name, String.to_atom(field_name))
    |> TodoplaceWeb.Live.Profile.Shared.open(__MODULE__)
  end
end
