defmodule TodoplaceWeb.ClientMessageComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.LiveModal, only: [close_x: 1, footer: 1]
  import TodoplaceWeb.Shared.Quill, only: [quill_input: 1]
  import Todoplace.Messages, only: [get_emails: 2]

  alias Todoplace.{
    Repo,
    Job,
    Clients,
    AdminGlobalSettings,
    Campaign,
    ClientMessage,
    EmailAutomationSchedules
  }

  @default_assigns %{
    composed_event: :message_composed,
    modal_title: "Send an email",
    send_button: "Send Email",
    client: nil,
    show_cc: false,
    show_bcc: false,
    show_client_email: true,
    show_subject: true,
    current_user: nil,
    enable_size: false,
    enable_image: false,
    manual_toggle: false,
    toggle_value: false,
    email_schedule: nil,
    booking_event?: nil
  }

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(Enum.into(assigns, @default_assigns))
    |> assign_new(:recipients, fn ->
      if Map.has_key?(assigns, :client), do: %{"to" => assigns.client.email}, else: nil
    end)
    |> then(&(&1 |> assign(:show_bcc, Map.has_key?(&1.assigns.recipients, "bcc"))))
    |> assign(:search_results, [])
    |> assign(:search_phrase, nil)
    |> assign(:current_focus, -1)
    |> assign_new(:bcc_email_error, fn -> nil end)
    |> assign_new(:cc_email_error, fn -> nil end)
    |> assign_new(:to_email_error, fn -> nil end)
    |> assign(
      :admin_global_settings,
      AdminGlobalSettings.get_all_active_settings() |> Map.new(&{&1.slug, &1})
    )
    |> then(fn %{assigns: assigns} = socket ->
      socket
      |> assign_changeset(:validate, Map.take(assigns, [:subject, :body_text, :body_html]))
    end)
    |> then(fn socket ->
      socket =
        socket
        |> assign_presets()

      if socket.assigns.show_client_email, do: re_assign_clients(socket), else: socket
    end)
    |> then(fn
      %{assigns: %{presets: [_ | _] = presets}} = socket ->
        assign(socket, preset_options: [{"none", ""} | Enum.map(presets, &{&1.name, &1.id})])

      socket ->
        assign(socket, preset_options: [])
    end)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal">
      <.close_x />
      <h1 class="text-3xl mb-4"><%= @modal_title %></h1>
      <%= if @show_client_email do %>
        <div class="flex flex-col">
          <label for="to_email" class="text-sm font-semibold mb-2">
            To:
            <span class="font-light text-sm ml-0.5 italic">
              (semicolon separated to add more emails)
            </span>
          </label>
          <div class="flex flex-col md:flex-row">
            <input
              type="text"
              class="w-full md:w-2/3 text-input"
              id="to_email"
              value={"#{get_emails(@recipients, "to")}"}
              phx-keyup="validate_to_email"
              phx-target={@myself}
              phx-debounce="1000"
              spellcheck="false"
            />
            <.search_existing_clients
              search_results={@search_results}
              search_phrase={@search_phrase}
              current_focus={@current_focus}
              clients={@clients}
              myself={@myself}
            />
          </div>
          <span class={classes("text-red-sales-300 text-sm", %{"hidden" => !@to_email_error})}>
            <%= @to_email_error %>
          </span>
        </div>

        <%= if @show_cc do %>
          <.show_optional_input
            email_type="cc"
            error={@cc_email_error}
            myself={@myself}
            recipients={@recipients}
          />
        <% end %>
        <%= if @show_bcc do %>
          <.show_optional_input
            email_type="bcc"
            error={@bcc_email_error}
            myself={@myself}
            recipients={@recipients}
          />
        <% end %>
        <div class="flex flex-row mt-4">
          <%= if !@show_cc do %>
            <.icon_button
              class="w-full md:w-28 justify-center bg-white border-blue-planning-300 text-black"
              phx-click="show-cc"
              phx-target={@myself}
              color="blue-planning-300"
              icon="plus"
            >
              Add Cc
            </.icon_button>
          <% end %>
          <%= if !@show_bcc do %>
            <.icon_button
              class="ml-2 w-full md:w-32 justify-center bg-white border-blue-planning-300 text-black"
              phx-click="show-bcc"
              phx-target={@myself}
              color="blue-planning-300"
              icon="plus"
            >
              Add Bcc
            </.icon_button>
          <% end %>
        </div>
        <hr class="my-4" />
      <% end %>

      <%= if @manual_toggle do %>
        <.manual_state_show
          email_schedule={@email_schedule}
          toggle_value={@toggle_value}
          myself={@myself}
        />
      <% end %>
      <.form :let={f} for={@changeset} phx-change="validate" phx-submit="save" phx-target={@myself}>
        <div class="grid grid-flow-row md:grid-flow-row md:auto-cols-fr md:gap-4 mt-2">
          <%= if Enum.any?(@preset_options),
            do:
              labeled_select(f, :preset_id, @preset_options,
                label: "Select email preset",
                class: "h-12"
              ) %>
          <%= if  @booking_event? do %>
            <label class="block mt-4 input-label">
              Subject line
              <span class="font-light text-sm ml-0.5 italic">(Use, edit or create your own)</span>
            </label>
            <%= input(f, :subject,
              wrapper_class: classes(hidden: !@show_subject),
              class: "h-12",
              phx_debounce: "500"
            ) %>
          <% else %>
            <%= labeled_input(f, :subject,
              label: "Subject line",
              wrapper_class: classes(hidden: !@show_subject),
              class: "h-12",
              phx_debounce: "500"
            ) %>
          <% end %>
        </div>
        <%= if  @booking_event? do %>
          <label class="block mt-4 input-label" for="editor">
            Message
            <span class="font-light text-sm ml-0.5 italic">(Use, edit or create your own)</span>
          </label>
        <% else %>
          <label class="block mt-4 input-label" for="editor">Message </label>
        <% end %>

        <.quill_input
          f={f}
          html_field={:body_html}
          text_field={:body_text}
          enable_size={@enable_size}
          enable_image={@enable_image}
          current_user={@current_user}
        />
        <.footer>
          <button
            class="btn-primary px-11"
            title={@send_button}
            type="submit"
            disabled={!@changeset.valid? || @to_email_error || @cc_email_error || @bcc_email_error}
            phx-disable-with="Sending..."
          >
            <%= @send_button %>
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
        </.footer>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("validate_bcc_email", %{"value" => email}, socket) do
    socket |> validate_emails(email, "bcc") |> noreply()
  end

  @impl true
  def handle_event("validate_cc_email", %{"value" => email}, socket) do
    socket |> validate_emails(email, "cc") |> noreply()
  end

  @impl true
  def handle_event("validate_to_email", %{"value" => email}, socket) do
    socket |> validate_emails(email, "to") |> noreply()
  end

  @impl true
  def handle_event("add-to", %{"client_email" => email}, socket) do
    prepend_email(email, "to", socket)
    |> noreply()
  end

  @impl true
  def handle_event("add-cc", %{"client_email" => email}, socket) do
    prepend_email(email, "cc", socket)
    |> assign(:show_cc, true)
    |> noreply()
  end

  @impl true
  def handle_event("add-bcc", %{"client_email" => email}, socket) do
    prepend_email(email, "bcc", socket)
    |> assign(:show_bcc, true)
    |> noreply()
  end

  @impl true
  def handle_event("show-cc", _, socket) do
    socket
    |> assign(:show_cc, true)
    |> noreply()
  end

  @impl true
  def handle_event("show-bcc", _, socket) do
    socket
    |> assign(:show_bcc, true)
    |> noreply()
  end

  @impl true
  def handle_event("remove-cc", _, %{assigns: %{recipients: recipients}} = socket) do
    socket
    |> assign(:show_cc, false)
    |> assign(:recipients, Map.put(recipients, "cc", []))
    |> assign(:cc_email_error, nil)
    |> then(fn socket -> socket |> re_assign_clients() end)
    |> noreply()
  end

  @impl true
  def handle_event("remove-bcc", _, %{assigns: %{recipients: recipients}} = socket) do
    socket
    |> assign(:show_bcc, false)
    |> assign(:recipients, Map.put(recipients, "bcc", []))
    |> assign(:bcc_email_error, nil)
    |> then(fn socket -> socket |> re_assign_clients() end)
    |> noreply()
  end

  @impl true
  def handle_event("toggle", %{"active" => active}, socket) do
    socket
    |> assign(:toggle_value, update_toggle(active))
    |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "client_message" => %{"preset_id" => preset_id},
          "_target" => ["client_message", "preset_id"]
        },
        %{assigns: %{presets: presets, job: job}} = socket
      ) do
    preset =
      case Integer.parse(preset_id) do
        :error ->
          %{subject_template: "", body_template: ""}

        {preset_id, _} ->
          presets
          |> Enum.find(&(Map.get(&1, :id) == preset_id))
          |> Todoplace.EmailPresets.resolve_variables({job}, TodoplaceWeb.Helpers)
      end

    socket
    |> assign_changeset(:validate, %{
      subject: preset.subject_template,
      body_html: preset.body_template,
      preset_id: preset_id
    })
    |> push_event("quill:update", %{"html" => remove_client_name(socket, preset.body_template)})
    |> noreply()
  end

  @impl true
  def handle_event("validate", %{"campaign" => params}, socket) do
    socket
    |> assign_changeset(:validate, params)
    |> noreply()
  end

  @impl true
  def handle_event("validate", %{"client_message" => params}, socket) do
    socket
    |> assign_changeset(:validate, params)
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        _params,
        %{
          assigns: %{
            email_schedule: email_schedule,
            toggle_value: toggle_value,
            changeset: changeset,
            composed_event: composed_event,
            recipients: recipients
          }
        } = socket
      ) do
    updated_recipients = remove_duplicate_recipients(recipients)

    if changeset.valid?,
      do:
        send(
          socket.parent_pid,
          {composed_event, changeset |> Map.put(:action, nil), updated_recipients}
        )

    if toggle_value and changeset.valid? do
      EmailAutomationSchedules.update_email_schedule(email_schedule.id, %{
        reminded_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
    end

    socket |> noreply()
  end

  def handle_event("email-preview", params, socket),
    do: TodoplaceWeb.Live.EmailAutomations.Show.handle_event("email-preview", params, socket)

  defdelegate handle_event(event, params, socket), to: TodoplaceWeb.JobLive.Shared

  @spec open(Phoenix.LiveView.Socket.t(), %{
          optional(:body_html) => String.t(),
          optional(:body_text) => any,
          optional(:composed_event) => any,
          optional(:modal_title) => String.t(),
          optional(:send_button) => String.t(),
          optional(:show_client_email) => boolean,
          optional(:show_subject) => boolean,
          optional(:subject) => String.t(),
          optional(:presets) => [Todoplace.EmailPresets.EmailPreset.t()],
          optional(:current_user) => Todoplace.Accounts.User.t(),
          optional(:client) => Todoplace.Client.t(),
          optional(:enable_size) => boolean,
          optional(:enable_image) => boolean,
          optional(:recipients) => map(),
          optional(:manual_toggle) => boolean,
          optional(:email_schedule) => any,
          optional(:for) => atom()
        }) :: Phoenix.LiveView.Socket.t()
  def open(%{assigns: assigns} = socket, opts \\ %{}),
    do:
      open_modal(
        socket,
        __MODULE__,
        %{
          assigns: Enum.into(opts, Map.take(assigns, [:job]))
        }
      )

  def client_email(%Job{client: %{email: email}}), do: email

  def remove_duplicate_recipients(recipients) do
    to = Map.get(recipients, "to") |> List.wrap() |> Enum.uniq()
    cc = (Map.get(recipients, "cc", []) |> Enum.uniq()) -- to
    bcc = ((Map.get(recipients, "bcc", []) |> Enum.uniq()) -- to) -- cc

    %{"to" => to}
    |> update_recipients_map("cc", cc)
    |> update_recipients_map("bcc", bcc)
  end

  defp update_recipients_map(map, _, []), do: map
  defp update_recipients_map(map, key, value), do: Map.put(map, key, value)

  defp assign_changeset(
         %{assigns: %{for: :campaign_reply, current_user: user}} = socket,
         action,
         params
       ) do
    params
    |> Map.put("organization_id", user.organization_id)
    |> process_params(socket)
    |> Campaign.outbound_changeset()
    |> Map.put(:action, action)
    |> then(&assign(socket, changeset: &1))
  end

  defp assign_changeset(
         socket,
         action,
         params
       ) do
    params
    |> process_params(socket)
    |> ClientMessage.create_outbound_changeset()
    |> Map.put(:action, action)
    |> then(&assign(socket, changeset: &1))
  end

  defp process_params(params, socket) do
    # need to check why it's trying to get :body_html when keys are strings
    body_html = remove_client_name(socket, Map.get(params, :body_html))

    Map.replace(params, :body_html, body_html)
  end

  defp assign_presets(%{assigns: %{job: %{} = job}} = socket),
    do: assign_new(socket, :presets, fn -> Todoplace.EmailPresets.for(job) end)

  defp assign_presets(socket), do: socket

  defp re_assign_clients(
         %{assigns: %{recipients: recipients, current_user: current_user}} = socket
       ) do
    if recipients do
      email_list = recipients |> Map.values() |> List.flatten()

      socket
      |> assign(
        :clients,
        Enum.filter(Clients.find_all_by(user: current_user), fn c -> c.email not in email_list end)
      )
    else
      socket
    end
  end

  defp prepend_email(
         email,
         type,
         %{assigns: %{recipients: recipients}} = socket
       ) do
    email_list =
      recipients
      |> Map.get(type, [])

    email = String.downcase(email)

    email_list =
      if is_list(email_list), do: List.insert_at(email_list, -1, email), else: [email, email_list]

    socket
    |> validate_emails(email_list, type)
    |> assign(:search_results, [])
    |> assign(:search_phrase, nil)
  end

  @error_2 ~s(please enter valid client emails that already exist in the system)
  @error_3 ~s(please enter valid emails)

  @to_slug ~s(to_limit)
  @cc_slug ~s(cc_limit)
  @bcc_slug ~s(bcc_limit)

  defp validate_emails(
         %{
           assigns: %{
             recipients: recipients,
             current_user: user,
             admin_global_settings: admin_global_settings
           }
         } = socket,
         emails,
         type
       ) do
    email_list = split_into_list(emails)

    %{value: value} =
      case type do
        "to" -> admin_global_settings[@to_slug]
        "cc" -> admin_global_settings[@cc_slug]
        "bcc" -> admin_global_settings[@bcc_slug]
      end

    value = String.to_integer(value)

    error =
      cond do
        length(email_list) > value ->
          "Limit reached, #{ngettext("1 email", "%{count} emails", value)} allowed, Contact support to increase limit"

        Enum.empty?(email_list) ->
          @error_3

        true ->
          nil
      end

    error = if error, do: error, else: do_validate_emails(email_list, type, user)

    socket
    |> assign(:"#{type}_email_error", error)
    |> assign(:recipients, Map.put(recipients, type, email_list))
    |> re_assign_clients()
  end

  defp do_validate_emails(email_list, type, _user) when type in ~w(cc bcc) do
    Enum.any?(email_list) &&
      Enum.all?(email_list, fn email ->
        String.match?(email, Todoplace.Accounts.User.email_regex())
      end)
      |> if(do: nil, else: @error_3)
  end

  defp do_validate_emails(email_list, type, user) when type == ~s(to) do
    Enum.any?(email_list) &&
      email_list
      |> Enum.all?(
        &(user
          |> Clients.get_client_query(email: &1)
          |> Repo.exists?())
      )
      |> if(do: nil, else: @error_2)
  end

  defp split_into_list(emails) when is_list(emails), do: emails

  defp split_into_list(emails) do
    emails
    |> String.downcase()
    |> String.split(";", trim: true)
    |> Enum.map(fn email ->
      String.trim(email)
    end)
  end

  defp remove_client_name(
         %{assigns: %{client: client}} = _socket,
         body_html
       ) do
    if is_nil(client) do
      body_html
    else
      if blank?(body_html) do
        body_html
      else
        greeting = body_html |> String.split() |> hd() |> String.replace("<p>", "")

        String.replace(
          body_html,
          "#{greeting} #{client.name |> String.split() |> hd()}",
          "#{greeting}"
        )
      end
    end
  end

  defp email_buttons() do
    [
      %{title: "Add to", action_event: "add-to"},
      %{title: "Add Cc", action_event: "add-cc"},
      %{title: "Add Bcc", action_event: "add-bcc"}
    ]
  end

  defp search_existing_clients(assigns) do
    ~H"""
    <div class="w-full md:w-1/3 md:ml-6">
      <%= form_tag("#", [phx_change: :search, phx_target: @myself]) do %>
        <div class="relative flex flex-col w-full md:flex-row">
          <a class="absolute top-0 bottom-0 flex flex-row items-center justify-center overflow-hidden text-xs text-gray-400 left-2">
            <%= if (Enum.any?(@search_results) && @search_phrase) do %>
              <span phx-click="clear-search" phx-target={@myself} class="cursor-pointer">
                <.icon
                  name="close-x"
                  class="w-4 ml-1 fill-current stroke-current stroke-2 close-icon text-blue-planning-300"
                />
              </span>
            <% else %>
              <.icon name="search" class="w-4 ml-1 fill-current" />
            <% end %>
          </a>
          <input
            type="text"
            class="form-control w-full text-input indent-6"
            id="search_phrase_input"
            name="search_phrase"
            value={"#{@search_phrase}"}
            phx-debounce="500"
            spellcheck="false"
            phx-target={@myself}
            placeholder="Search clients to add to email..."
          />
          <%= if Enum.any?(@search_results) && @search_phrase do %>
            <div
              id="search_results"
              class="absolute top-14 w-full z-50 left-0 right-0 rounded-lg border border-gray-100 shadow py-2 px-2 bg-white"
            >
              <%= for search_result <- Enum.take(@search_results, 5) do %>
                <div {testid("search-row")} class="flex items-center cursor-pointer p-3">
                  <div class="w-full">
                    <p class="font-bold"><%= search_result.name %></p>
                    <p class="text-sm"><%= search_result.email %></p>
                    <div class="flex justify-between mt-2">
                      <%= for %{title: title, action_event: event} <- email_buttons() do %>
                        <.add_icon_button
                          title={title}
                          click_event={event}
                          myself={@myself}
                          search_result={search_result}
                        />
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <%= if @search_phrase && @search_phrase && Enum.empty?(@search_results) do %>
              <div class="absolute top-14 w-full z-50">
                <div class="z-50 left-0 right-0 rounded-lg border border-gray-100 cursor-pointer shadow py-2 px-2 bg-white">
                  <p class="font-bold">No clients found with that info</p>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp show_optional_input(assigns) do
    ~H"""
    <div clas="flex flex-col">
      <div class="flex flex-row mt-4 md:items-center mb-2">
        <label for={"#{@email_type}_email"} class="text-sm font-semibold">
          <%= String.capitalize(@email_type) %>:
          <span class="font-light text-sm ml-0.5 italic">
            (semicolon separated to add more emails)
          </span>
        </label>
        <.icon_button_
          class="ml-10 w-8 bg-white border-red-sales-300 py-1 px-2"
          title={"remove-#{@email_type}"}
          phx-click={"remove-#{@email_type}"}
          phx-target={@myself}
          color="red-sales-300"
          icon="trash"
          icon_class="w-4 h-4"
        />
      </div>
      <div class="flex flex-col">
        <input
          type="text"
          class="w-full md:w-2/3 text-input"
          id={"#{@email_type}_email"}
          value={
            if Map.has_key?(@recipients, @email_type),
              do: "#{Enum.join(Map.get(@recipients, @email_type, []), "; ")}",
              else: ""
          }
          phx-keyup={"validate_#{@email_type}_email"}
          phx-target={@myself}
          phx-debounce="1000"
          spellcheck="false"
          placeholder="enter email(s)…"
        />
        <span
          {testid("#{@email_type}-error")}
          class={classes("text-red-sales-300 text-sm", %{"hidden" => !@error})}
        >
          <%= @error %>
        </span>
      </div>
    </div>
    """
  end

  defp add_icon_button(assigns) do
    ~H"""
    <.icon_button_
      class="w-auto sm:w-28 justify-center bg-gray-100 text-black text-sm"
      title={@title}
      phx-click={@click_event}
      phx-target={@myself}
      phx-value-client_email={"#{@search_result.email}"}
      color="blue-planning-300"
      icon="plus"
    >
      <%= @title %>
    </.icon_button_>
    """
  end

  defp icon_button_(assigns) do
    assigns =
      assigns
      |> Map.put(
        :rest,
        Map.drop(assigns, [:color, :icon, :inner_block, :class, :disabled, :icon_class])
      )
      |> Enum.into(%{class: "", disabled: false, inner_block: nil, icon_class: nil})

    ~H"""
    <button
      type="button"
      class={
        classes(
          "btn-tertiary flex items-center py-1 font-sans rounded-lg hover:opacity-75 transition-colors text-#{@color} #{@class}",
          %{"opacity-50 hover:opacity-30 hover:cursor-not-allowed" => @disabled}
        )
      }
      }
      disabled={@disabled}
      {@rest}
    >
      <.icon
        name={@icon}
        class={
          classes("w-3 h-3 fill-current text-#{@color} #{@icon_class}", %{"mr-1" => @inner_block})
        }
      />
      <%= if @inner_block do %>
        <%= render_slot(@inner_block) %>
      <% end %>
    </button>
    """
  end

  defp manual_state_show(assigns) do
    ~H"""
    <div class="p-5 flex flex-col rounded-lg bg-gray-100 lg:w-1/2">
      <div class="flex flex-row mb-5 items-center">
        <div class="w-9 h-9 rounded-full bg-gray-200 flex items-center justify-center">
          <.icon name="play-icon" class="inline-block w-5 h-5 fill-current text-blue-planning-300" />
        </div>
        <div class="ml-3">
          <p class="text-sm uppercase font-bold text-base-250">Email Sequences</p>
          <p class="text-blue-planning-300 text-2xl font-bold"><%= @email_schedule.name %></p>
        </div>
      </div>
      <div class="flex flex-row ml-12">
        <.form for={%{}} class="flex">
          <label class="flex">
            <input
              id="pipeline-toggle"
              phx-target={@myself}
              phx-click="toggle"
              phx-value-active={@toggle_value |> to_string}
              type="checkbox"
              class="peer hidden"
              checked={@toggle_value}
            />
            <div class="hidden peer-checked:flex">
              <div class="rounded-full bg-blue-planning-300 border border-base-100 w-16 h-8 p-1 flex items-center justify-end mr-4 hover:cursor-pointer">
                <div class="rounded-full h-5 w-5 bg-base-100"></div>
              </div>
            </div>
            <div class="flex peer-checked:hidden">
              <div class="rounded-full w-16 h-8 p-1 flex items-center mr-4 border border-blue-planning-300 hover:cursor-pointer">
                <div class="rounded-full h-5 w-5 bg-blue-planning-300"></div>
              </div>
            </div>
          </label>
          <div>
            <p class="font-bold">Allow automation to send sequence</p>
            <p>(Disable to send a one-off)</p>
            <p
              class="text-blue-planning-300 underline hover:cursor-pointer"
              phx-target={@myself}
              phx-click="email-preview"
              phx-value-email-preview-id={@email_schedule.id}
              phx-value-is-preview="true"
            >
              <a>Preview email</a>
            </p>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp update_toggle("true"), do: false
  defp update_toggle("false"), do: true
end
