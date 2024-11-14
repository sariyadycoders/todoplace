defmodule TodoplaceWeb.GallerySessionController do
  use TodoplaceWeb, :controller

  alias Todoplace.Galleries
  alias Todoplace.Repo

  def gallery_login(conn, %{"hash" => hash, "login" => %{"session_token" => token}}) do
    gallery =
      hash
      |> Galleries.get_gallery_by_hash!()
      |> Repo.preload([:albums])

    conn
    |> put_session("gallery_session_token", token)
    |> redirect_to(gallery)
  end

  defp redirect_to(conn, %{type: :standard, client_link_hash: hash}) do
    redirect(conn, to: ~p"/gallery/#{hash}")
  end

  defp redirect_to(conn, %{albums: [%{client_link_hash: hash}]}) do
    redirect(conn, to: ~p"/album/#{hash}")
  end
end
