defmodule TodoplaceWeb.FinanceExportController do
  use TodoplaceWeb, :controller
  require Logger

  def csv(conn, %{"token" => token}) do
    case Phoenix.Token.verify(TodoplaceWeb.Endpoint, "CSV-filename", token, max_age: :infinity) do
      {:ok, file_name} ->
        file_path = build_file_path(file_name)

        if File.exists?(file_path) do
          download(conn, file_path, "text/csv")
        else
          send_resp(conn, 404, "File not found")
        end

      {:error, e} ->
        Logger.info("Token Error #{e}")
        send_resp(conn, 404, "File not found")
    end
  end

  defp build_file_path(token) do
    "tmp/csv_exports/#{token}.csv"
  end

  defp download(conn, file_path, content_type) do
    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"#{Path.basename(file_path)}\""
    )
    |> send_file(200, file_path)
  end
end
