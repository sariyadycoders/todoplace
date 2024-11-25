defmodule TodoplaceWeb.OrganizationLive.CreateOrganizationComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias Todoplace.{Profiles, Organization, Workers.CleanStore}

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(:edit, true)
    |> assign(:entry, nil)
    |> assign(:meta, nil)
    |> assign(:filesize, nil)
    |> assign(:filename, "")
    |> assign(:display_progress_bar, true)
    |> assign(:disable_image_save_button, true)
    |> assign(assigns)
    |> assign_new(:organization, fn -> %Organization{} end)
    |> assign_changeset()
    |> allow_upload(
      :logo,
      accept: ~w(.svg .png),
      max_file_size: String.to_integer(Application.get_env(:todoplace, :logo_max_size)),
      max_entries: 1,
      external: &brand_logo_preflight/2,
      progress: &handle_image_progress/3,
      auto_upload: true
    )
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col modal p-30">
      <div class="flex items-start justify-between flex-shrink-0">
        <h1 class="mb-4 text-3xl font-bold">
          Create Organization
        </h1>

        <button
          phx-click="modal"
          phx-value-action="close"
          title="close modal"
          type="button"
          class="p-2"
        >
          <.icon name="close-x" class="w-3 h-3 stroke-current stroke-2 sm:stroke-1 sm:w-6 sm:h-6" />
        </button>
      </div>
      <div phx-hook="SetCurrentPath" id="SetCurrentPath"></div>
      <.form :let={f} for={@changeset} phx-submit="submit" phx-change="validate" phx-target={@myself}>
        <%= labeled_input(f, :name,
          placeholder: "Organization Name",
          phx_debounce: "500",
          wrapper_class: "mb-4"
        ) %>

        <.drag_image_upload
          icon_class={select_icon_class(@entry, @entry && @entry.upload_config == :logo)}
          uploads={@uploads}
          organization={@organization}
          edit={@edit}
          image_upload={@uploads.logo}
          disable_image_save_button={@disable_image_save_button}
          display_progress_bar={@display_progress_bar}
          myself={@myself}
          supports="PNG or SVG: under 10 mb"
          image_title="logo"
          meta={@meta}
          filename={@filename}
          filesize={@filesize}
        />
        <div>
          <div class="flex flex-col py-6 bg-white gap-2 sm:flex-row-reverse">
            <button
              class="px-8 btn-primary"
              title="Save"
              disabled={!@changeset.valid?}
              phx-target={@myself}
            >
              Save
            </button>
            <button
              class="btn-secondary"
              title="cancel"
              type="button"
              phx-click="modal"
              phx-value-action="close"
            >
              Cancel
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  defp drag_image_upload(assigns) do
    assigns = assigns |> Enum.into(%{class: "", label_class: "", supports_class: ""})

    ~H"""
    <label class={"w-full h-full flex items-center py-32 justify-center font-bold font-sans border border-#{@icon_class} border-2 border-dashed rounded-lg cursor-pointer #{@label_class}"}>
      <%= if !@disable_image_save_button && !is_nil(@meta) do %>
        <div class="flex flex-col w-full items-center">
          <div class="w-full sm:w-1/2 h-60 flex justify-center">
            <img src={make_url(@meta)} class="object-contain" />
          </div>

          <div class="w-full sm:w-1/2 flex my-4 p-4 items-start justify-center grid grid-cols-2">
            <div class="mr-auto">
              <p class="text-left sm:hidden">
                <%= trim_filename(@filename, "text-left sm:hidden") %>
              </p>
              <p class="text-left hidden sm:block"><%= trim_filename(@filename) %></p>
            </div>
            <div class="flex flex-row">
              <p class="ml-auto"><%= @filesize %></p>
              <span
                phx-click="confirm-delete-image"
                phx-target={@myself}
                phx-value-image-field={@image_title}
                class="cursor-pointer"
              >
                <.icon
                  name="trash"
                  class="relative inline-block w-5 h-5 ml-10 sm:ml-16 bottom-1 text-base-250 hover:opacity-75"
                />
              </span>
            </div>
          </div>
        </div>
      <% else %>
        <.icon name="upload" class={"w-10 h-10 mr-5 stroke-current text-#{@icon_class}"} />
        <div class={@supports_class}>
          Drag your <%= @image_title %> or <span class={"text-#{@icon_class}"}>browse</span>
          <p class="text-sm font-normal text-base-250">Supports <%= @supports %></p>
        </div>
        <.live_file_input upload={@image_upload} class="hidden" />
      <% end %>
    </label>

    <div data-testid="modal-buttons" class="bg-white -bottom-6">
      <%= if @display_progress_bar do %>
        <.progress
          image={@image_upload}
          class="flex m-4 items-center justify-center grid grid-cols-2"
          disabled={@display_progress_bar}
        />
      <% end %>
    </div>
    """
  end

  defp progress(assigns) do
    assigns = assigns |> Enum.into(%{class: ""})

    ~H"""
    <%= for %{progress: progress} <- @image.entries do %>
      <div class={@class}>
        <div>
          <p class="font-bold font-sans">
            <%= if progress == 100, do: "Upload complete!", else: "Uploading..." %>
          </p>
        </div>
        <div class="flex w-full h-2 rounded-lg bg-base-200">
          <div class="h-full rounded-lg bg-blue-planning-300" style={"width: #{progress}%"}></div>
        </div>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_event(
        "cancel-image-upload",
        _,
        %{assigns: %{meta: meta, uploads: %{logo: %{entries: [entry]}}}} = socket
      ) do
    if entry.progress == 100, do: CleanStore.new(%{path: make_url(meta)}) |> Oban.insert!()

    socket
    |> put_flash(:error, "Image uploading cancelled")
    |> cancel_image_uploading()
    |> noreply()
  end

  @impl true
  def handle_event(
        "cancel-image-upload",
        _,
        %{assigns: %{uploads: %{logo: %{entries: []}}}} = socket
      ),
      do: socket |> close_modal() |> noreply()

  def handle_event(
        "validate",
        %{"organization" => params},
        %{assigns: %{organization: organization}} = socket
      ) do
    socket
    |> assign_changeset(:validate, params)
    |> noreply()
  end

  @impl true
  def handle_event(
        "submit",
        %{"organization" => %{"name" => name}},
        %{assigns: %{organization_page: organization_page?, user_data: user_data}} = socket
      ) do
    %{current_user: current_user} = user_data
    params = Map.merge(%{name: name}, make_params(socket))

    Organization.create_organization(params, current_user.id)
    |> case do
      {:ok, organization} ->
        Todoplace.Cache.refresh_current_user_cache(user_data.session_token)

        Phoenix.PubSub.broadcast(
          Todoplace.PubSub,
          "organization:#{current_user.id}",
          {:update_organization_list, 1}
        )

        if organization_page? do
          send(socket.parent_pid, {:update, organization, "Successfully organization is created"})
        end

        socket
        |> close_modal()
        |> noreply()

      {:error, _} ->
        socket
        |> put_flash(:error, "Error while creating organization")
        |> cancel_image_uploading()
        |> noreply()
    end
  end

  @impl true
  def handle_event("validate-image", _params, socket), do: socket |> noreply()

  @impl true
  def handle_event(
        "confirm-delete-image",
        _,
        %{assigns: %{uploads: %{logo: %{entries: [_entry]}}}} = socket
      ) do
    socket
    |> cancel_image_uploading()
    |> noreply()
  end

  def handle_image_progress(:logo, %{done?: false}, socket), do: socket |> noreply()

  def handle_image_progress(
        :logo,
        %{done?: true},
        %{assigns: %{uploads: %{logo: %{entries: [entry]}}}} = socket
      ) do
    {:ok, filesize} = Size.humanize(entry.client_size)

    socket
    |> assign(disable_image_save_button: false)
    |> assign(filesize: filesize)
    |> assign(filename: entry.client_name)
    |> assign(display_progress_bar: false)
    |> noreply()
  end

  # def open(%{assigns: %{current_user: current_user}} = socket) do
  #   socket
  #   |> open_modal(__MODULE__, %{
  #     current_user: current_user
  #     # organization: organization
  #   })
  # end

  defp cancel_image_uploading(%{assigns: %{uploads: %{logo: %{entries: [entry]}}}} = socket) do
    socket
    |> cancel_upload(entry.upload_config, entry.ref)
    |> assign(meta: nil)
    |> assign(entry: nil)
    |> assign(filename: "")
    |> assign(filesize: nil)
    |> assign(disable_image_save_button: true)
    |> assign(display_progress_bar: true)
  end

  defp build_changeset(
         %{assigns: %{organization: organization}},
         params
       ) do
    Organization.name_changeset(organization, params)
  end

  defp assign_changeset(socket, action \\ nil, params \\ %{}) do
    changeset = build_changeset(socket, params) |> Map.put(:action, action)

    assign(socket, changeset: changeset)
  end

  defp make_url(meta), do: meta.url <> "/" <> meta.fields["key"]

  defp make_params(%{assigns: %{uploads: %{logo: %{entries: [entry]}}, meta: meta}} = _socket),
    do: %{
      profile: %{
        logo: %{
          id: entry.uuid,
          url: make_url(meta),
          content_type: entry.client_type
        }
      }
    }

  defp make_params(_socket), do: %{}

  defp validate_entry(socket, %{valid?: is_valid} = entry) do
    if is_valid do
      socket
    else
      socket
      |> put_flash(:error, "Image was too large, needs to be below 10 mb")
      |> cancel_upload(entry.upload_config, entry.ref)
    end
  end

  defp trim_filename(filename, class \\ "") do
    extension =
      String.split(filename, ~r/\.[A-Za-z]+/, include_captures: true, trim: true) |> List.last()

    trimmed_filename = "#{String.slice(filename, 0..9)}.. #{extension}"

    cond do
      String.length(filename) > 17 && class == "text-left sm:hidden" -> trimmed_filename
      String.length(filename) >= 25 && class == "" -> trimmed_filename
      true -> filename
    end
  end

  defp select_icon_class(%{valid?: false}, true), do: "red-sales-300"
  defp select_icon_class(_entry, _), do: "blue-planning-300"

  defp brand_logo_preflight(image, %{assigns: %{organization: organization}} = socket) do
    {:ok, meta} = Profiles.brand_logo_preflight(image, organization)
    {:ok, meta, assign(socket, meta: meta)}
  end
end
