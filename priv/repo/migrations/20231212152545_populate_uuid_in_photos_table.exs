defmodule Todoplace.Repo.Migrations.PopulateUuidInPhotosTable do
  use Ecto.Migration
  alias Todoplace.Repo
  import Ecto.Query

  def change do
    from(q in "photos", where: is_nil(q.uuid), select: %{id: q.id})
    |> Repo.all()
    |> Enum.each(fn photo ->
      execute("""
        UPDATE photos
        SET uuid = '#{UUID.uuid4()}'
        WHERE id=#{photo.id}
      """)
    end)
  end
end
