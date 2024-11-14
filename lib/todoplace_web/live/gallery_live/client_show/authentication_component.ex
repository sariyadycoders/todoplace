defmodule TodoplaceWeb.GalleryLive.ClientShow.AuthenticationComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Todoplace.{Galleries, Galleries.Gallery}
  import Todoplace.Profiles, only: [logo_url: 1]

  def mount(socket) do
    socket
    |> assign(:password_is_correct, true)
    |> assign(:submit, false)
    |> assign(:session_token, nil)
    |> ok()
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_password_change()
    |> ok()
  end

  def handle_event("change", %{"login" => params}, socket) do
    socket
    |> assign_password_change(params)
    |> noreply()
  end

  def handle_event(
        "check",
        %{"login" => %{"email" => email, "password" => password}},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    check_login(socket, email, gallery, password)
    |> noreply()
  end

  def handle_event(
        "check",
        %{"login" => %{"email" => email}},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    check_login(socket, email, gallery, nil)
    |> noreply()
  end

  def maybe_show_logo?(%{gallery: %{job: %{client: %{organization: organization}}}} = assigns) do
    assigns = Map.put(assigns, :organization, organization)

    ~H"""
      <%= case logo_url(@organization) do %>
        <% nil -> %> <h1 class="pt-3 text-3xl font-light font-client text-base-300 mb-2 text-center"><%= @organization.name %></h1>
        <% url -> %> <img class="h-20 mx-auto" src={url} />
      <% end %>
      <.welcome_message />
    """
  end

  def maybe_show_logo?(assigns) do
    ~H"""
    <h1 class="pt-3 text-2xl font-light font-client text-base-300 text-center mb-2">Welcome!</h1>
    <.welcome_message />
    """
  end

  def welcome_message(assigns) do
    ~H"""
    <p class="text-base-300/75 text-center">Welcome! To view your gallery and access any digital image and print credits, enter the email address that matches the inbox to which you received your gallery link and password below.</p>
    """
  end

  defp assign_password_change(socket, params \\ %{}) do
    params
    |> Galleries.gallery_password_change()
    |> then(&assign(socket, :password_changeset, &1))
  end

  defp update_emails_map(email, gallery) do
    new_email_map = %{
      "email" => email,
      "viewed_at" => DateTime.utc_now()
    }

    email_list = gallery.gallery_analytics || []
    updated_email_list = email_list ++ [new_email_map]

    Galleries.update_gallery(gallery, %{gallery_analytics: updated_email_list})
  end

  defp check_login(socket, email, gallery, password) do
    valid_email? = String.length(email) > 0 && Regex.match?(~r/^[^\s]+@[^\s]+.[^\s]+$/, email)

    with true <- valid_email?,
         {:ok, token} <- check_gallery_password(gallery, email, password) do
      update_emails_map(String.downcase(email), gallery)
      assign(socket, submit: true, session_token: token)
    else
      _ ->
        assign(socket, password_is_correct: false)
    end
  end

  defp check_gallery_password(%Gallery{is_password: false} = gallery, email, nil) do
    gallery
    |> Galleries.build_gallery_session_token(String.downcase(email))
  end

  defp check_gallery_password(gallery, email, password) do
    gallery
    |> Galleries.build_gallery_session_token(password, String.downcase(email))
  end
end
