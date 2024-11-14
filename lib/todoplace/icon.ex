defmodule Todoplace.Icon do
  @moduledoc "helpers to ensure validity of icons svg"

  @svg_file "images/icons.svg"
  @external_resource "assets/static/#{@svg_file}"
  @svg_content File.read!(@external_resource)

  @names ~r/id="([\w-]+)"/
         |> Regex.scan(@svg_content)
         |> Enum.map(&List.last/1)
         |> tap(&([] = &1 -- Enum.uniq(&1)))

  def names, do: @names

  def public_path(id, conn, static_path) when id in @names,
    do: static_path.(conn, "/#{@svg_file}") <> "##{id}"
end
