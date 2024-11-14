defmodule TodoplaceWeb.Live.ClientLive.Show do
  @moduledoc false
  use TodoplaceWeb, :live_view

  import TodoplaceWeb.Live.ClientLive.{Shared, Index}
  import TodoplaceWeb.JobLive.Shared, only: [card: 1]

  alias Todoplace.{Clients, Client}
  alias TodoplaceWeb.Live.ClientLive

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket
    |> get_client(id)
    |> assign(:job_types, Todoplace.JobType.all())
    |> assign(:tags_changeset, ClientLive.Index.tag_default_changeset(%{}))
    |> ok()
  end

  @impl true
  def handle_params(%{"edit" => "true"} = params, _, %{assigns: %{client: client}} = socket) do
    socket
    |> TodoplaceWeb.Live.ClientLive.ClientFormComponent.open(client)
    |> is_mobile(params)
    |> noreply()
  end

  @impl true
  def handle_params(params, _, socket) do
    socket
    |> is_mobile(params)
    |> noreply()
  end

  @impl true
  def handle_event("back_to_navbar", _, %{assigns: %{is_mobile: is_mobile}} = socket) do
    socket |> assign(:is_mobile, !is_mobile) |> noreply
  end

  @impl true
  defdelegate handle_event(name, params, socket), to: ClientLive.Index

  def handle_info({:update, %{client: client}}, socket) do
    socket
    |> assign(:client, client)
    |> put_flash(:success, "Client updated successfully")
    |> noreply()
  end

  @impl true
  defdelegate handle_info(message, socket), to: ClientLive.Index

  defp get_client(%{assigns: %{current_user: user}} = socket, id) do
    case Clients.get_client(user, id: id) do
      %Client{} = client ->
        socket |> assign(:client, client)

      nil ->
        socket |> redirect(to: "/clients")
    end
  end
end
