defmodule Todoplace.Designs do
  @moduledoc """
    context module for whcc designs
  """
  import Ecto.Query, only: [from: 2]
  alias Todoplace.Repo
  import Todoplace.Repo.CustomMacros

  def load_occasion(occasion_id) do
    from(designs in active(),
      limit: 1,
      where: designs.api ~> "occasion" ~>> "_id" == ^occasion_id,
      select: designs.api ~> "occasion"
    )
    |> Repo.one()
    |> case do
      %{"_id" => id, "name" => name} -> %{id: id, name: name}
      _ -> nil
    end
  end

  def occasion_designs_query(%{id: "" <> occasion_id}), do: occasion_designs_query(occasion_id)

  def occasion_designs_query("" <> occasion_id) do
    from(designs in active(), where: designs.api ~> "occasion" ~>> "_id" == ^occasion_id)
  end

  def occasions() do
    from(designs in active(),
      join: face in jsonb_path_query(designs.api, "$.faces[0]"),
      on: true,
      join: preview in jsonb_path_query(face, "$.layouts[0].previews.keyvalue().value", :first),
      on: true,
      where: face ~> "height" |> type(:float) > face ~> "width" |> type(:float),
      group_by: 1,
      select: {designs.api ~> "occasion", preview |> jsonb_agg() ~> 0}
    )
    |> Repo.all()
    |> Enum.map(fn {%{"_id" => id, "name" => name}, preview_url} ->
      %{id: id, name: name, preview_url: preview_url}
    end)
  end

  def designs_query(), do: active() |> designs_query()

  def designs_query(filtered_designs) do
    photo_slots_query =
      from(designs in filtered_designs,
        join: faces in jsonb_path_query(designs.api, "$.faces[*]"),
        on: true,
        group_by: designs.id,
        select: %{
          design_id: designs.id,
          slots: faces |> jsonb_path_query("$.layouts[*].photoCount", :array) |> jsonb_agg()
        }
      )

    from(designs in filtered_designs,
      join:
        preview in jsonb_path_query(
          designs.api,
          "$.faces[0].layouts[0].previews.keyvalue().value",
          :first
        ),
      on: true,
      join: product in assoc(designs, :product),
      join: photo_slots in subquery(photo_slots_query),
      on: photo_slots.design_id == designs.id,
      order_by: [asc: designs.position],
      select: %{
        id: designs.id,
        whcc_id: designs.whcc_id,
        name: designs.api ~> "displayName",
        photo_slots: photo_slots.slots,
        preview_url: fragment("?", preview),
        product: struct(product, [:whcc_id])
      }
    )
  end

  def single_design_front_query(id), do: active() |> single_design_front_query(id)

  def single_design_front_query(filtered_designs, id) do
    photo_slots_query =
      from(designs in filtered_designs,
        join: faces in jsonb_path_query(designs.api, "$.faces[*]"),
        on: true,
        group_by: designs.id,
        select: %{
          design_id: designs.id,
          slots: faces |> jsonb_path_query("$.layouts[*].photoCount", :array) |> jsonb_agg()
        }
      )

    from(designs in filtered_designs,
      join:
        preview in jsonb_path_query(
          designs.api,
          "$.faces[0].layouts[0].previews.keyvalue().value",
          :first
        ),
      on: true,
      join: product in assoc(designs, :product),
      join: photo_slots in subquery(photo_slots_query),
      on: photo_slots.design_id == designs.id,
      order_by: [asc: designs.position],
      select: %{
        id: designs.id,
        whcc_id: designs.whcc_id,
        name: designs.api ~> "displayName",
        photo_slots: photo_slots.slots,
        preview_url: fragment("?", preview),
        product: struct(product, [:whcc_id])
      },
      where: designs.id == ^id
    )
  end

  def single_design_back_query(id), do: active() |> single_design_back_query(id)

  def single_design_back_query(filtered_designs, id) do
    photo_slots_query =
      from(designs in filtered_designs,
        join: faces in jsonb_path_query(designs.api, "$.faces[*]"),
        on: true,
        group_by: designs.id,
        select: %{
          design_id: designs.id,
          slots: faces |> jsonb_path_query("$.layouts[*].photoCount", :array) |> jsonb_agg()
        }
      )

    from(designs in filtered_designs,
      join:
        preview in jsonb_path_query(
          designs.api,
          "$.faces[1].layouts[0].previews.keyvalue().value",
          :first
        ),
      on: true,
      join: product in assoc(designs, :product),
      join: photo_slots in subquery(photo_slots_query),
      on: photo_slots.design_id == designs.id,
      order_by: [asc: designs.position],
      select: %{
        id: designs.id,
        whcc_id: designs.whcc_id,
        name: designs.api ~> "displayName",
        photo_slots: photo_slots.slots,
        preview_url: fragment("?", preview),
        product: struct(product, [:whcc_id])
      },
      where: designs.id == ^id
    )
  end

  defdelegate active(), to: Todoplace.Design
end
