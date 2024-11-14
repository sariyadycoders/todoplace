defmodule TodoplaceWeb.InboxLive.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view

  alias Todoplace.{Job, Jobs, Repo, Notifiers.ClientNotifier, Messages, Marketing, Clients}

  import Todoplace.Galleries.Workers.PhotoStorage, only: [path_to_url: 1]

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(:page_title, "Inbox")
    |> assign_unread()
    |> subscribe_inbound_messages()
    |> assign(:current_thread_type, nil)
    |> assign(:tabs, tabs_list())
    |> ok()
  end

  @impl true
  def handle_params(%{"id" => thread_id} = params, _uri, socket) do
    [current_thread_type, thread_id] = String.split(thread_id, "-")

    socket
    |> assign_tab(params)
    |> assign(:current_thread_type, String.to_atom(current_thread_type))
    |> assign_tab_data()
    |> assign_unread()
    |> assign_current_thread(thread_id)
    |> noreply()
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket
    |> assign_tab(params)
    |> assign_tab_data()
    |> noreply()
  end

  defp assign_tab(socket, params), do: assign(socket, :tab_active, params["type"] || "all")

  @impl true
  def render(assigns) do
    ~H"""
    <div class={classes(%{"hidden lg:block" => @current_thread})} {intro(@current_user, "intro_inbox")}><h1 class="px-6 py-10 text-4xl font-bold center-container" {testid("inbox-title")}>Inbox</h1></div>
    <div class={classes("center-container pb-6", %{"pt-0" => @current_thread})}>
      <div class={classes("flex flex-col lg:flex-row bg-gray-100 py-6 items-center mb-6 px-4 rounded-lg", %{"hidden lg:flex" => @current_thread})}>
        <h2 class="font-bold text-2xl mb-4">Viewing all messages</h2>
        <div class="flex lg:ml-auto gap-3">
          <%= for %{name: name, action: action, concise_name: concise_name} <- @tabs do %>
            <button class={classes("border rounded-lg border-blue-planning-300 text-blue-planning-300 py-1 px-4", %{"text-white bg-blue-planning-300" => @tab_active === concise_name, "hover:opacity-100" => @tab_active !== concise_name})} type="button" phx-click={action} phx-value-tab={concise_name}><%=  name %></button>
          <% end %>
        </div>
      </div>

      <div class="flex lg:h-[calc(100vh-18rem)]">
        <div class={classes("border-t w-full lg:w-1/3 overflow-y-auto flex-shrink-0", %{"hidden lg:block" => @current_thread, "hidden" => Enum.empty?(@threads)})}>
          <%= for thread <- @threads do %>
            <.thread_card {thread} unread={member?(assigns, thread)} selected={@current_thread && to_string(thread.id) == @current_thread.id && @current_thread_type == thread.type} />
          <% end %>
        </div>
        <%= cond do %>
          <% @current_thread != nil -> %>
            <.current_thread {@current_thread} current_thread_type={@current_thread_type} socket={@socket} />
          <% Enum.empty?(@threads) -> %>
            <div class="flex w-full items-center justify-center p-6 border m-5">
              <div class="flex items-center flex-col text-blue-planning-300 text-xl">
                <.icon name="envelope" class="text-blue-planning-300 w-20 h-20" />
                <p class="text-center">You don’t have any new messages.</p>
                <p class="text-center">Go to a job or lead to send a new message.</p>
              </div>
            </div>
          <% true -> %>
            <div class="hidden lg:flex w-2/3 items-center justify-center border ml-4 rounded-lg">
              <div class="flex items-center">
                <.icon name="envelope" class="text-blue-planning-300 w-20 h-32" />
                <p class="ml-4 text-blue-planning-300 text-xl w-52">No message selected</p>
              </div>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp thread_card(assigns) do
    ~H"""
    <div {testid("thread-card")} phx-click="open-thread" phx-value-id={@id} phx-value-type={@type} class={classes("flex flex-col lg:flex-row justify-between py-6 border-b pl-2 p-8 cursor-pointer", %{"bg-blue-planning-300 rounded-lg text-white" => @selected, "hover:bg-gray-100 hover:text-black" => !@selected})}>
      <div class="px-4 order-2 lg:order-1">
        <div class="flex items-center">
          <div class="font-bold	text-2xl lg:hidden">
            <%= title_slice(@title, 26) %>
          </div>
          <div class="font-bold	text-2xl hidden lg:block">
            <%= title_slice(@title, 12) %>
          </div>
          <%= if @unread do %>
            <span {testid("new-badge")} class="mx-4 px-2 py-0.5 text-xs rounded bg-orange-inbox-300 text-white">New</span>
          <% end %>
        </div>
        <div class=" font-semibold py-0.5 hidden lg:block lg:line-clamp-1">
           <%= @subtitle %>
        </div>
        <div class=" font-semibold py-0.5 lg:hidden">
           <%=  subtitle_slice(@subtitle, 30) %>
        </div>

        <%= if (@subject) do %>
          <div class="line-clamp-1"><%= raw @subject %></div>
        <% end %>
        <span class="px-2 py-0.5 text-xs font-semibold rounded bg-blue-planning-100 text-blue-planning-300">
          <%= case @type do %>
            <% type when type in [:campaign, :campaign_reply] -> %>
              <%= if @outbound, do: "Marketing campaign", else: "Marketing reply" %>
            <% type -> %>
              <%= type |> to_string() |> String.capitalize() %>
          <% end %>
        </span>
      </div>
      <div class="relative flex flex-shrink-0 pl-4 text-xs order-1 lg:order-2">
        <%= @date %>
        <.icon name="forth" class="sm:hidden absolute top-1.5 -right-6 w-4 h-4 stroke-current text-base-300 stroke-2" />
      </div>
    </div>
    """
  end

  defp toggle_icon(assigns) do
    ~H"""
      <%= if @collapsed_sections do %>
        <.icon name="down" class="w-4 h-4 stroke-current stroke-2" />
      <% else %>
        <.icon name="up" class="w-4 h-4 stroke-current stroke-2" />
      <% end %>
    """
  end

  defp current_thread(assigns) do
    ~H"""
      <div class="flex flex-col w-full lg:overflow-y-auto lg:border rounded-lg ml-2">
          <div class="sticky z-10 top-0 px-6 py-3 flex shadow-sm lg:shadow-none bg-base-200">
            <.live_link to={~p"/inbox"} class="lg:hidden pt-2 pr-4">
              <.icon name="left-arrow" class="w-6 h-6" />
            </.live_link>
            <div>
              <div class="sm:font-semibold text-2xl line-clamp-1 text-blue-planning-300"><%= @title %></div>
            </div>
            <button title="Delete" type="button" phx-click="confirm-delete" class="ml-auto flex items-center hover:opacity-80">
              <.icon name="trash" class="sm:w-5 sm:h-5 w-6 h-6 mr-3 text-red-sales-300" />
            </button>
          </div>
            <div class="bg-white sticky top-14 z-10 pt-4">
              <div class="flex items-center ml-4">
                <%= case @current_thread_type do %>
                  <% type when type in [:client, :campaign_reply] -> %>
                    <.icon name="client-icon" class="text-blue-planning-300 w-6 h-6 mr-2" />
                    <.view_link name="View client" route={~p"/clients/#{@id}"} />
                  <% type when type in [:job, :lead] -> %>
                    <.icon name="camera-check" class="text-blue-planning-300 w-6 h-6 mr-2" />
                    <%= if @is_lead do %>
                      <.view_link name="View lead" route={~p"/leads/#{@id}"} />
                    <% else %>
                      <.view_link name="View job" route={~p"/jobs/#{@id}"} />
                    <% end %>
                  <% :campaign -> %>
                    <.icon name="marketing-inbox" class="text-blue-planning-300 w-6 h-6 mr-2" />
                    <.view_link name="View marketing campaign" route={~p"/marketing/#{@id}"} />
                <% end %>
              </div>
              <hr class="my-4 sm:my-4" />
            </div>
          <div class="flex flex-1 flex-col p-6">
            <%= for message <- @messages do %>
              <%= if message.is_first_unread do %>
                <div class="flex items-center my-1">
                  <div class="flex-1 h-px bg-orange-inbox-300"></div>
                  <div class="text-orange-inbox-300 px-4">new message</div>
                  <div class="flex-1 h-px bg-orange-inbox-300"></div>
                </div>
              <% end %>

              <div {testid("thread-message")} {scroll_to_message(message)} class="m-2" style="scroll-margin-bottom: 7rem">
                <div class={classes("mb-3 flex justify-between items-end", %{"flex-row-reverse" => message.outbound})}>

                  <div class="mx-1">
                    <%= unless message.same_sender do %>
                      <%= message.sender %> wrote:
                    <% end %>
                  </div>
                </div>

                <div class={classes("flex flex-col sm:flex-row items-center justify-between font-bold text-xl px-4 py-2", %{"rounded-t-lg" => message.collapsed_sections, "rounded-lg" => !message.collapsed_sections, "bg-blue-planning-300 text-white" => message.outbound, "bg-gray-200" => !message.outbound})} phx-click="collapse-section" phx-value-id={message.id}>
                  <div class="flex justify-between items-center w-full sm:w-auto">
                    <div>
                      <%= message.subject %>
                      <%= if message.unread do %>
                          <span {testid("new-badge")} class="mx-4 px-2 py-0.5 text-xs rounded bg-orange-inbox-300 text-white">New</span>
                      <% end %>
                    </div>
                    <div class="sm:hidden">
                      <.toggle_icon collapsed_sections={message.collapsed_sections} />
                    </div>
                  </div>
                  <div class="flex gap-2 text-xs w-1/3 justify-end ml-auto sm:ml-0">
                    <%= message.date %>
                    <span class="hidden sm:block">
                      <.toggle_icon collapsed_sections={message.collapsed_sections} />
                    </span>
                  </div>
                </div>
                <%= if message.collapsed_sections do %>
                  <div class="flex border px-4 py-2 text-base-250">
                    <div class="flex flex-col">
                      <%= if @current_thread_type in [:campaign, :campaign_reply] and is_list(message.receiver) and length(message.receiver) > 1 do %>
                        <p> Sent to <%= Enum.count(message.receiver) %> clients </p>
                        <div phx-click="show-cc" phx-value-id={message.id} class="text-blue-planning-300 cursor-pointer">See all</div>
                      <% else %>
                        <p> To: <%= if is_list(message.receiver), do: hd(message.receiver), else: message.receiver %> </p>
                      <% end %>

                      <%= if(message.show_cc?) do %>
                        <%= if @current_thread_type in [:campaign, :campaign_reply] do %>
                          <p class="flex flex-wrap">
                            <% last = List.last(message.receiver) %>
                            <%= for reciever <- message.receiver do %>
                              <span> <%= reciever %><%= if last != reciever, do: ";" %> </span>
                            <% end %>
                          </p>
                        <% else %>
                          <p> Cc: <%= message.cc %> </p>
                          <p> Bcc: <%= message.bcc %> </p>
                        <% end %>
                      <% end %>
                    </div>
                    <div class={"ml-auto text-blue-planning-300 underline cursor-pointer #{@current_thread_type in [:client, :campaign, :campaign_reply] && 'hidden'}"} phx-click="show-cc" phx-value-id={message.id}>
                      <%= if(message.show_cc?) do %>
                        Hide Cc/Bcc
                      <% else %>
                        Show Cc/Bcc
                      <% end %>
                    </div>
                  </div>
                  <div class="flex flex-col relative border rounded-b-lg p-6">
                    <span class="whitespace-pre-line"><%= raw message.body %></span>

                    <%= unless Enum.empty?(message.client_message_attachments) do %>
                      <div class="p-2 border mt-4 rounded-lg">
                        <h4 class="text-sm mb-2 font-bold">Client attachments:</h4>
                        <div class="flex flex-col gap-2">
                          <%= for client_attachment <- message.client_message_attachments do %>
                            <a href={path_to_url(client_attachment.url)} target="_blank">
                              <div class="text-sm text-blue-planning-300 bg-base-200 border border-base-200 hover:bg-white transition-colors duration-300 px-2 py-1 rounded-lg flex items-center">
                                <.icon name="paperclip" class="w-4 h-4 mr-1" /> <%= client_attachment.name %>
                              </div>
                            </a>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <%= if message.read_at do %>
                      <span class="ml-auto text-base-250 text-sm">
                          <%= message.read_at %>
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

          </div>
          <div class="sticky bottom-0 bg-white flex flex-col p-6 sm:pr-8 bg-white sm:flex-row-reverse">
            <%= unless @current_thread_type == :campaign do %>
              <button class="btn-primary" phx-click="compose-message" phx-value-thread-id={@id}>
                Reply
              </button>
            <% end %>
          </div>
      </div>
    """
  end

  defp view_link(assigns) do
    ~H"""
      <.live_link to={@route} class="flex gap-2 items-center rounded-lg bg-gray-100 py-1 px-4 text-blue-planning-300">
        <%= @name %>
        <.icon name="forth" class="stroke-2 h-3 w-2 mt-1" />
      </.live_link>
    """
  end

  defp member?(
         %{
           unread_job_ids: unread_job_ids,
           unread_client_ids: unread_client_ids,
           unread_campaign_ids: unread_campaign_ids
         },
         %{type: type} = thread
       ) do
    case type do
      :job ->
        is_map_key(unread_job_ids, thread.id)

      :client ->
        is_map_key(unread_client_ids, thread.id)

      _ ->
        campaign_id = if Map.get(thread, :campaign_id), do: thread.campaign_id, else: thread.id
        is_map_key(unread_campaign_ids, campaign_id)
    end
  end

  def scroll_to_message(message) do
    if message.scroll do
      %{phx_hook: "ScrollIntoView", id: "message-#{message.id}"}
    else
      %{}
    end
  end

  @impl true
  def handle_event(
        "open-thread",
        %{"id" => id, "type" => type},
        socket
      ) do
    path = "#{type}-#{id}?#{%{type: type}}"

    socket
    |> push_patch(to: ~p"/inbox/#{path}")
    |> noreply()
  end

  @impl true
  def handle_event("change-tab", %{"tab" => tab}, socket) do
    socket
    |> push_patch(to: ~p"/inbox?#{%{type: tab}}")
    |> noreply()
  end

  @impl true
  def handle_event("show-cc", %{"id" => id}, socket) do
    new_messages =
      Enum.map(socket.assigns.current_thread.messages, fn entry ->
        if entry.id == String.to_integer(id) do
          show_cc? = Map.get(entry, :show_cc?, false)
          Map.update!(entry, :show_cc?, fn _ -> !show_cc? end)
        else
          entry
        end
      end)

    socket
    |> assign(
      :current_thread,
      %{
        socket.assigns.current_thread
        | messages: new_messages
      }
    )
    |> noreply()
  end

  @impl true
  def handle_event(
        "collapse-section",
        %{"id" => id},
        %{assigns: %{current_thread: %{messages: messages} = current_thread}} = socket
      ) do
    new_messages =
      Enum.map(messages, fn entry ->
        if entry.id == String.to_integer(id) do
          collapsed_sections = Map.get(entry, :collapsed_sections, false)
          Map.update!(entry, :collapsed_sections, fn _ -> !collapsed_sections end)
        else
          entry
        end
      end)

    socket
    |> assign(:current_thread, %{current_thread | messages: new_messages})
    |> noreply()
  end

  @impl true
  def handle_event(
        "compose-message",
        %{},
        %{assigns: %{job: job, current_user: current_user, current_thread_type: :job}} = socket
      ) do
    socket
    |> TodoplaceWeb.ClientMessageComponent.open(%{
      subject: Job.name(job),
      current_user: current_user,
      enable_size: true,
      enable_image: true,
      client: Job.client(job)
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "compose-message",
        %{"thread-id" => thread_id},
        %{assigns: %{current_user: current_user, current_thread_type: thread_type}} = socket
      ) do
    client =
      if thread_type == :lead,
        do: get_client_for_lead(thread_id),
        else: Todoplace.Clients.get_client!(thread_id)

    socket
    |> TodoplaceWeb.ClientMessageComponent.open(
      %{
        current_user: current_user,
        enable_size: true,
        enable_image: true,
        client: client
      }
      |> then(fn
        opts when thread_type == :campaign_reply ->
          Map.merge(opts, %{
            show_client_email: false,
            for: :campaign_reply,
            composed_event: :message_composed_for_campaign_reply
          })

        opts ->
          opts
      end)
    )
    |> noreply()
  end

  @impl true
  def handle_event("confirm-delete", %{}, socket) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      close_label: "Cancel",
      confirm_event: "delete",
      confirm_label: "Yes, delete",
      icon: "warning-orange",
      title: "Remove Conversation?",
      subtitle: "This will remove the conversation from Inbox and cannot be undone."
    })
    |> noreply()
  end

  @impl true
  def handle_event("intro_js" = event, params, socket),
    do: TodoplaceWeb.LiveHelpers.handle_event(event, params, socket)

  defp get_client_for_lead(id) do
    id
    |> Job.by_id()
    |> Repo.one()
    |> Repo.preload([:client])
    |> Map.get(:client)
    |> Map.get(:id)
    |> Clients.get_client!()
  end

  defp assign_threads(%{assigns: %{current_user: current_user, tab_active: tab}} = socket) do
    tab
    |> then(fn
      type when type in ["lead", "job"] ->
        Messages.job_threads(current_user)

      "client" ->
        Messages.client_threads(current_user)

      "campaign" ->
        Messages.campaigns_threads(current_user)

      "all" ->
        current_user
        |> Messages.job_threads()
        |> Enum.concat(Messages.client_threads(current_user))
        |> Enum.concat(Messages.campaigns_threads(current_user))
    end)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.map(&build_thread(&1, current_user))
    |> then(&assign(socket, :threads, &1))
  end

  defp build_thread(
         %{client_message_recipients: client_message_recipients} = message,
         current_user
       ) do
    %{
      id: message.job_id || hd(client_message_recipients).client_id,
      title: thread_title(message),
      subtitle: if(message.job, do: Job.name(message.job), else: "CLIENTS SUBTITLE"),
      message: if(message.body_html, do: message.body_html, else: message.body_text),
      subject: message.subject || "",
      type: thread_type(message),
      outbound: message.outbound,
      date: strftime(current_user.time_zone, message.inserted_at, "%a %b %d, %-I:%M %p")
    }
  end

  defp build_thread(campaign, current_user) do
    type = thread_type(campaign)

    %{
      id: (type == :campaign && campaign.id) || hd(campaign.campaign_clients).client_id,
      campaign_id: campaign.id,
      title: thread_title(campaign),
      subtitle: if(campaign.parent_id, do: "Campaign reply", else: "Campaign"),
      message: if(campaign.body_html, do: campaign.body_html, else: campaign.body_text),
      subject: campaign.subject || "",
      type: type,
      outbound: type == :campaign,
      date: strftime(current_user.time_zone, campaign.inserted_at, "%a %b %d, %-I:%M %p")
    }
  end

  defp assign_unread(%{assigns: %{current_user: current_user}} = socket) do
    {job_ids, client_ids, campaign_ids, message_ids} = Messages.unread_messages(current_user)

    socket
    |> assign(:unread_message_ids, Map.new(message_ids, &{&1, &1}))
    |> assign(:unread_job_ids, Map.new(job_ids, &{&1, &1}))
    |> assign(:unread_client_ids, Map.new(client_ids, &{&1, &1}))
    |> assign(:unread_campaign_ids, Map.new(campaign_ids, &{&1, &1}))
  end

  defp assign_current_thread(socket, thread_id, message_id_to_scroll \\ nil)

  defp assign_current_thread(
         %{assigns: %{current_thread_type: thread_type}} = socket,
         thread_id,
         message_id_to_scroll
       )
       when thread_type in [:job, :lead] do
    %{client: %{name: name}, job_status: job_status} =
      job = Jobs.get_job_by_id(thread_id) |> Repo.preload([:client, :job_status])

    client_messages = Messages.for_job(job)

    socket
    |> assign(:current_thread, %{
      id: thread_id,
      messages: build_messages(socket, client_messages, message_id_to_scroll),
      title: name,
      subtitle: Job.name(job),
      is_lead: job_status.is_lead
    })
    |> assign(:job, job)
    |> mark_current_thread_as_read()
  end

  defp assign_current_thread(
         %{
           assigns: %{
             current_thread_type: :client
           }
         } = socket,
         thread_id,
         message_id_to_scroll
       ) do
    client = Todoplace.Clients.get_client!(thread_id)
    client_messages = Messages.for_client(client)

    socket
    |> assign(:current_thread, %{
      id: thread_id,
      messages: build_messages(socket, client_messages, message_id_to_scroll),
      title: client.name,
      subtitle: "Client Subtitle",
      is_lead: false
    })
    |> assign(:job, nil)
    |> assign(:client, client)
    |> mark_current_thread_as_read()
  end

  defp assign_current_thread(
         %{
           assigns: %{
             current_thread_type: thread_type
           }
         } = socket,
         thread_id,
         message_id_to_scroll
       )
       when thread_type in [:campaign, :campaign_reply] do
    campaigns =
      case thread_type do
        :campaign -> [Todoplace.Marketing.get_campaign(thread_id)]
        :campaign_reply -> Todoplace.Marketing.get_campaign_replies(thread_id)
      end

    socket
    |> assign(:current_thread, %{
      id: thread_id,
      messages: build_messages(socket, campaigns, message_id_to_scroll),
      title: "Sent marketing campaign",
      subtitle: "Campaign subtitle",
      is_lead: false
    })
    |> then(fn
      socket when thread_type == :campaign -> socket
      socket -> mark_current_thread_as_read(socket)
    end)
  end

  defp build_messages(
         %{
           assigns: %{
             current_user: %{time_zone: time_zone},
             current_thread_type: thread_type
           }
         } = socket,
         messages,
         message_id_to_scroll
       ) do
    length = length(messages)

    messages
    |> Enum.with_index(1)
    |> Enum.reduce(%{last: nil, messages: []}, fn
      {message, index}, %{last: last, messages: messages} ->
        {outbound, last_outbound, {sender, receiver}, member?} =
          message_items(socket, message, last)

        build_message(
          {messages, message, time_zone, outbound, sender, receiver, last_outbound, member?,
           message_id_to_scroll, index, length, thread_type}
        )
    end)
    |> Map.get(:messages)
  end

  defp message_items(socket, message, last) do
    %{
      assigns: %{
        unread_message_ids: unread_message_ids,
        unread_campaign_ids: unread_campaign_ids,
        current_thread_type: thread_type
      }
    } = socket

    case message do
      %{campaign_clients: campaign_clients, parent_id: parent_id} ->
        outbound = is_nil(parent_id)
        last_outbound = last && is_nil(last.parent_id)

        {sender, receiver} = get_sender_receiver(message, campaign_clients)

        {outbound, last_outbound, {sender, receiver},
         Enum.member?(unread_campaign_ids, message.id)}

      %{client_message_recipients: recipients, outbound: outbound} ->
        last_outbound = last && last.outbound

        {sender, receiver} =
          message
          |> extract_client()
          |> get_sender_receiver(recipients, outbound, thread_type)

        {outbound, last_outbound, {sender, receiver},
         Enum.member?(unread_message_ids, message.id)}
    end
  end

  defp build_message(message_items) do
    {messages, message, time_zone, outbound, sender, receiver, last_outbond, is_first_unread,
     message_id_to_scroll, index, length, thread_type} = message_items

    %{body_text: body_text, body_html: body_html, read_at: read_at} = message

    %{
      last: message,
      messages:
        messages ++
          [
            %{
              id: message.id,
              body: if(body_html, do: body_html, else: body_text),
              date: strftime(time_zone, message.inserted_at, "%a %b %-d, %-I:%0M %p"),
              outbound: outbound,
              sender: sender,
              receiver: receiver,
              cc: assign_message_recipients(message, :cc, thread_type),
              bcc: assign_message_recipients(message, :bcc, thread_type),
              subject: message.subject,
              same_sender: last_outbond == outbound,
              is_first_unread: is_first_unread,
              scroll: message.id == message_id_to_scroll || index == length,
              unread: message.read_at == nil,
              client_message_attachments: message.client_message_attachments,
              show_cc?: false,
              collapsed_sections: true,
              read_at: if(read_at, do: strftime(time_zone, read_at, "%a, %B %d, %I:%M:%S %p"))
            }
          ]
    }
  end

  defp get_sender_receiver(client, recipients, outbound, type) when type in [:job, :lead] do
    sender = (outbound && "You") || client.name
    recipient = Enum.find(recipients, &(&1.recipient_type == :to))
    client = (recipient && recipient.client) || client
    receiver = (outbound && client.email) || "You"

    {sender, receiver}
  end

  defp get_sender_receiver(client, _recipients, outbound, :client) do
    sender = (outbound && "You") || client.name
    receiver = (outbound && client.email) || "You"

    {sender, receiver}
  end

  defp get_sender_receiver(message, campaign_clients) do
    case message do
      %{parent_id: nil} ->
        {"You", Enum.map(campaign_clients, & &1.client.email)}

      _ ->
        client = extract_client(message)

        {client.name, "You"}
    end
  end

  defp assign_message_recipients(_, _, thread_type)
       when thread_type in [:campaign, :campaign_reply],
       do: []

  defp assign_message_recipients(%{client_message_recipients: client_message_recipients}, type, _) do
    client_message_recipients
    |> Enum.filter(&(&1.recipient_type == type))
    |> Enum.map(& &1.client_id)
    |> Clients.fetch_multiple()
    |> case do
      [] -> nil
      clients -> Enum.map_join(clients, ";", & &1.email)
    end
  end

  @tabs [{"All", "all"}, {"Jobs/Leads", "job"}, {"Clients", "client"}, {"Marketing", "campaign"}]
  defp tabs_list() do
    Enum.map(@tabs, fn {name, concise_name} ->
      %{
        name: name,
        concise_name: concise_name,
        action: "change-tab"
      }
    end)
  end

  defp assign_tab_data(socket) do
    socket
    |> assign_threads()
    |> assign(:current_thread, nil)
  end

  defp mark_current_thread_as_read(
         %{assigns: %{current_thread: %{id: id}, current_thread_type: type}} = socket
       ) do
    if connected?(socket) do
      Messages.update_all(id, type, :read_at)
    end

    socket
  end

  alias Phoenix.PubSub

  defp subscribe_inbound_messages(
         %{assigns: %{current_user: %{organization_id: org_id}}} = socket
       ) do
    PubSub.subscribe(Todoplace.PubSub, "inbound_messages:#{org_id}")

    socket
  end

  def handle_info(
        {:inbound_messages, message},
        %{assigns: %{current_thread: current_thread}} = socket
      ) do
    socket
    |> assign_threads()
    |> assign_unread()
    |> then(fn socket ->
      if current_thread do
        assign_current_thread(socket, current_thread.id, message.id)
      else
        socket
      end
    end)
    |> noreply()
  end

  def handle_info(
        {:message_composed, message_changeset, recipients},
        %{assigns: assings} = socket
      ) do
    {thread_id, message_result} = insert_messages_query(message_changeset, recipients, assings)

    with {:ok, %{client_message: message}} <- Repo.transaction(message_result),
         {:ok, _email} <- ClientNotifier.deliver_email(message, recipients) do
      socket
      |> assign_threads()
      |> assign_current_thread(thread_id, message.id)
    else
      _error ->
        socket |> put_flash(:error, "Something went wrong")
    end
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Email sent",
      subtitle: "Yay! Your email has been successfully sent"
    })
    |> noreply()
  end

  def handle_info(
        {:message_composed_for_campaign_reply, changeset, %{"to" => [clinet_email]}},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      ) do
    client = Clients.client_by_email(organization_id, clinet_email)

    case Marketing.save_campaign(changeset, [client]) do
      {:ok, %{campaign: campaign}} ->
        socket
        |> assign_threads()
        |> assign_current_thread(to_string(client.id), campaign.id)

      _error ->
        socket |> put_flash(:error, "Something went wrong")
    end
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      title: "Email sent",
      subtitle: "Yay! Your email has been successfully sent"
    })
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "delete"},
        %{
          assigns: %{
            current_thread_type: thread_type,
            current_thread: current_thread,
            tab_active: tab
          }
        } = socket
      ) do
    Messages.update_all(current_thread.id, thread_type, :deleted_at)

    socket
    |> close_modal()
    |> push_redirect(to: ~p"/inbox?#{%{type: tab}}", replace: true)
    |> noreply()
  end

  defp title_slice(title, digit) do
    length = String.length(title)

    if length > digit do
      String.slice(title, 0..digit) <> "..."
    else
      title
    end
  end

  defp subtitle_slice(subtitle, digit) do
    if String.length(subtitle) > digit do
      String.slice(subtitle, 0..div(digit, 3)) <>
        "..." <> " " <> (String.split(subtitle, " ") |> List.last())
    else
      subtitle
    end
  end

  defp insert_messages_query(message_changeset, recipients, %{
         current_user: user,
         job: %{client: _client} = job
       }) do
    {job.id, Messages.add_message_to_job(message_changeset, job, recipients, user)}
  end

  defp insert_messages_query(message_changeset, recipients, %{current_user: user, client: client}) do
    {client.id, Messages.add_message_to_client(message_changeset, recipients, user)}
  end

  defp extract_client(%{client_message_recipients: [%{client: client} | _]}), do: client
  defp extract_client(%{job: %{client: client}}), do: client
  defp extract_client(%{campaign_clients: [%{client: client} | _]}), do: client

  defp thread_type(%{job_id: nil}), do: :client

  defp thread_type(%{job_id: _job_id} = message) do
    %{job: %{job_status: job_status}} = Repo.preload(message, job: :job_status)
    if job_status.is_lead, do: :lead, else: :job
  end

  defp thread_type(%{campaign_clients: [_]}), do: :campaign_reply
  defp thread_type(%{parent_id: nil}), do: :campaign

  defp thread_title(%{client_message_recipients: [%{client: %{name: name}} | _]}), do: name
  defp thread_title(%{job: %{client: %{name: name}}}), do: name
  defp thread_title(%{campaign_clients: [%{client: %{name: name}}]}), do: name
  defp thread_title(%{parent_id: nil}), do: "Sent marketing campaign"
end
