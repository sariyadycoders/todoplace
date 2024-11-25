defmodule TodoplaceWeb.Shared.ImageUploadInput do
  @moduledoc """
    Helper functions to use the image upload input component
  """
  use TodoplaceWeb, :live_component

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Enum.into(%{
        id: "image-upload-input",
        class: "",
        resize_height: 650,
        uploading: false,
        supports: "Supports JPEG or PNG: 1060x707 under 10mb",
        url: nil
      })

    ~H"""
    <div
      id={"#{@id}-wrapper"}
      class={@class}
      phx-hook="ImageUploadInput"
      class="mt-2"
      data-target={@myself}
      data-upload-folder={@upload_folder}
      data-resize-height={@resize_height}
    >
      <input type="hidden" name={@name} value={@url} />
      <input type="file" class="hidden" {testid("image-upload-input")} />

      <%= cond do %>
        <% @uploading -> %>
          <div class="w-full h-full flex flex-col items-center justify-center p-4 font-bold border border-blue-planning-300 border-2 border-dashed rounded-lg text-xs aspect-[6/4]">
            <div class="w-3 h-3 m-2 rounded-full opacity-75 bg-blue-planning-300 animate-ping"></div>
            Uploading...
          </div>
        <% @url != "" and not is_nil(@url) -> %>
          <div class="w-full h-full flex items-center justify-center relative aspect-[6/4]">
            <%= if assigns[:image_slot] do %>
              <%= render_slot(@image_slot) %>
            <% else %>
              <img src={@url} class="h-full w-full object-cover" />
            <% end %>
            <div class="upload-button absolute top-5 right-4 rounded-3xl bg-white shadow-lg cursor-pointer flex p-3 py-2 items-center justify-center">
              <span class="text-blue-planning-300 text-normal hover:opacity-75">
                Replace Photo
              </span>
              <.icon name="trash" class="w-4 h-4 ml-2 text-blue-planning-300" />
            </div>
          </div>
        <% true -> %>
          <div class="upload-button w-full h-full flex flex-col items-center justify-center p-4 font-bold border border-blue-planning-300 border-2 border-dashed rounded-lg cursor-pointer aspect-[6/4]">
            <%= if @uploading do %>
            <% else %>
              <.icon name="upload" class="w-10 h-10 mb-2 stroke-current text-blue-planning-300" />
              <p>Drag your image or <span class="text-blue-planning-300">browse</span></p>
              <p class="text-sm font-normal text-base-250"><%= @supports %></p>
            <% end %>
          </div>
      <% end %>
    </div>
    """
  end

  def image_upload_input(assigns) do
    ~H"""
    <.live_component module={__MODULE__} id={assigns[:id] || "image_upload_input"} {assigns} />
    """
  end

  @impl true
  def handle_event(
        "get_signed_url",
        %{"name" => name, "type" => type, "upload_folder" => upload_folder},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    path =
      [
        [current_user.organization.slug, upload_folder],
        ["#{:os.system_time(:millisecond)}-#{name}"]
      ]
      |> Enum.concat()
      |> Path.join()

    params =
      Todoplace.Galleries.Workers.PhotoStorage.params_for_upload(
        expires_in: 600,
        bucket: bucket(),
        key: path,
        field: %{
          "content-type" => type,
          "cache-control" => "public, max-age=@upload_options"
        },
        conditions: [
          [
            "content-length-range",
            0,
            String.to_integer(Application.get_env(:todoplace, :photo_max_file_size))
          ]
        ]
      )

    socket
    |> assign(uploading: true)
    |> reply(params)
  end

  @impl true
  def handle_event("upload_finished", %{"url" => url}, socket) do
    socket
    |> assign(uploading: false, url: url)
    |> noreply()
  end

  defp config(), do: Application.get_env(:todoplace, :profile_images)
  defp bucket, do: Keyword.get(config(), :bucket)
end
