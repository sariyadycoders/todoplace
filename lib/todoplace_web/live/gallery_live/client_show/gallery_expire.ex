defmodule TodoplaceWeb.GalleryLive.ClientShow.GalleryExpire do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: "live_client"]
  import TodoplaceWeb.Live.Profile.Shared, only: [photographer_logo: 1]
  alias Todoplace.{Galleries, Profiles}

  @impl true
  def handle_params(%{"hash" => hash}, _, socket) do
    gallery = Galleries.get_gallery_by_hash!(hash) |> Galleries.populate_organization_user()
    {organization, gallery_user} = extract_gallery(gallery)
    url = Profiles.public_url(organization)

    socket
    |> assign(%{profile_url: url, organization: organization, gallery_user: gallery_user})
    |> noreply()
  end

  defp extract_gallery(%{
         job: %{client: %{organization: %{user: gallery_user} = organization}}
       }) do
    {organization, gallery_user}
  end
end
