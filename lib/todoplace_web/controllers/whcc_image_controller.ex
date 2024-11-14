defmodule TodoplaceWeb.WhccImageController do
  use TodoplaceWeb, :controller
  require Logger
  alias Todoplace.Galleries.{Workers.PhotoStorage, Photo}
  @key "Image-Path"

  def image(conn, %{"encrypted_path" => encrypted_path}) do
    case Phoenix.Token.verify(TodoplaceWeb.Endpoint, @key, encrypted_path, max_age: :infinity) do
      {:ok, path} ->
        photo =
          Todoplace.Repo.get_by(Photo,
            original_url: path
          )

        conn |> process_photo(photo)

      {:error, e} ->
        Logger.info("Token Error #{e}")

        conn
        |> put_status(:not_found)
        |> put_view(TodoplaceWeb.ErrorView)
        |> render("404.html")
    end
  end

  defp process_photo(conn, photo) do
    %HTTPoison.AsyncResponse{id: id} =
      photo.original_url
      |> PhotoStorage.path_to_url()
      |> HTTPoison.get!(%{}, stream_to: self())

    conn
    |> put_resp_header("content-disposition", encode_header_value(photo.name))
    |> send_chunked(200)
    |> process_chunks(id)
  end

  def encode_header_value(filename) do
    "attachment; filename*=UTF-8''" <> encode_filename(filename)
  end

  defp encode_filename(value) do
    URI.encode(value, fn
      x when ?0 <= x and x <= ?9 -> true
      x when ?A <= x and x <= ?Z -> true
      x when ?a <= x and x <= ?z -> true
      _ -> false
    end)
  end

  defp process_chunks(conn, id) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id} ->
        process_chunks(conn, id)

      %HTTPoison.AsyncHeaders{id: ^id} ->
        process_chunks(conn, id)

      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk_data} ->
        chunk(conn, chunk_data)
        process_chunks(conn, id)

      %HTTPoison.AsyncEnd{id: ^id} ->
        conn
    end
  end
end

defmodule TodoplaceWeb.WhccImageHTML do
  use TodoplaceWeb, :html
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]
  import TodoplaceWeb.ViewHelpers

  embed_templates "templates/*"
end
