defmodule TodoplaceWeb.Live.Profile.EditWebsiteComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal !max-w-xl">
      <h1 class="text-3xl font-bold">Edit Link</h1>

      <.form :let={f} for={@changeset} phx-change="validate" phx-submit="save" phx-target={@myself}>
        <%= for b <- inputs_for(f, :brand_links) do %>
          <%= hidden_inputs_for(b) %>
          <.website_field form={b} class="mt-4" placeholder="Add your website…" />
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

  def open(socket), do: TodoplaceWeb.Live.Profile.Shared.open(socket, __MODULE__)
end
