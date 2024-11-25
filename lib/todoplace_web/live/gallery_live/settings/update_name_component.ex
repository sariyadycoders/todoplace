defmodule TodoplaceWeb.GalleryLive.Settings.UpdateNameComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Todoplace.Galleries

  import TodoplaceWeb.GalleryLive.Shared, only: [disabled?: 1]

  @impl true
  def update(%{id: id, gallery: gallery}, socket) do
    {:ok,
     socket
     |> assign(:id, id)
     |> assign(:gallery, gallery)
     |> assign_gallery_changeset()}
  end

  @impl true
  def handle_event("validate", %{"gallery" => %{"name" => name}}, socket) do
    socket
    |> assign_gallery_changeset(%{name: name})
    |> noreply
  end

  @impl true
  def handle_event(
        "save",
        %{"gallery" => %{"name" => name}},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    {:ok, gallery} = Galleries.update_gallery(gallery, %{name: name})
    send(self(), {:update_name, %{gallery: gallery}})
    socket |> noreply
  end

  @impl true
  def handle_event("reset", _params, socket) do
    %{assigns: %{gallery: gallery}} = socket

    socket
    |> assign(:gallery, Galleries.reset_gallery_name(gallery))
    |> assign_gallery_changeset()
    |> noreply
  end

  defp assign_gallery_changeset(%{assigns: %{gallery: gallery}} = socket),
    do:
      socket
      |> assign(:changeset, Galleries.change_gallery(gallery) |> Map.put(:action, :validate))

  defp assign_gallery_changeset(%{assigns: %{gallery: gallery}} = socket, attrs),
    do:
      socket
      |> assign(
        :changeset,
        Galleries.change_gallery(gallery, attrs) |> Map.put(:action, :validate)
      )

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full">
      <.form
        :let={f}
        for={@changeset}
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
        id="updateGalleryNameForm"
        class="flex flex-col items-start h-full"
      >
        <h3 class="font-sans">Gallery name</h3>
        <%= text_input(f, :name,
          disabled: disabled?(@gallery),
          class: "galleryName gallerySettingsInput mt-auto"
        ) %>
        <button
          type="button"
          phx-click="reset"
          phx-target={@myself}
          class={
            classes("mt-2 font-bold cursor-pointer text-blue-planning-300 lg:pt-0", %{
              "pointer-events-none text-gray-200" => disabled?(@gallery)
            })
          }
        >
          Reset
        </button>
        <div class="flex justify-end mt-auto w-full">
          <%= submit("Save",
            id: "saveGalleryName",
            class: "btn-settings font-sans w-32 px-11 cursor-pointer",
            disabled: !@changeset.valid? || disabled?(@gallery),
            phx_disable_with: "Saving..."
          ) %>
        </div>
      </.form>
    </div>
    """
  end
end
