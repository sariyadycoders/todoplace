defmodule TodoplaceWeb.Live.FinancesManage.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view

  import TodoplaceWeb.Live.Shared, only: [save_filters: 3]

  import TodoplaceWeb.Shared.CustomPagination,
    only: [
      pagination_component: 1,
      assign_pagination: 2,
      update_pagination: 2,
      reset_pagination: 2,
      pagination_index: 2
    ]

  import TodoplaceWeb.Live.FinancesManage.Shared,
    only: [
      split_and_assign_date_range: 2,
      get_galleries_orders: 1,
      get_payment_schedules: 1,
      sort_options: 0,
      apply_sort: 3
    ]

  alias Ecto.Changeset
  alias Todoplace.{PaymentSchedules, PreferredFilter, Orders}
  alias TodoplaceWeb.Live.FinancesManage.OnlinePaymentViewComponent

  @default_pagination_limit 12

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(:page_title, "Finances Overview")
    |> assign_pagination(@default_pagination_limit)
    |> assign_finances()
    |> ok()
  end

  @impl true
  def handle_info({:csv_export_done, download_url}, socket) do
    # Push event for export download
    socket
    |> push_event("trigger_download", %{url: download_url})
    |> put_flash(:success, "Export successful — check your downloads")
    |> close_modal()
    |> noreply()
  end

  @impl true
  def handle_info(:csv_export_failed, socket) do
    # Close modal and handle failure
    socket
    |> put_flash(:error, "Export failed — please try again")
    |> close_modal()
    |> noreply()
  end

  @impl true
  def handle_event(
        "page",
        %{"direction" => _direction} = params,
        socket
      ) do
    socket
    |> update_pagination(params)
    |> fetch_finances()
    |> noreply()
  end

  @impl true
  def handle_event(
        "page",
        %{"custom_pagination" => %{"limit" => _limit}} = params,
        socket
      ) do
    socket
    |> update_pagination(params)
    |> fetch_finances()
    |> noreply()
  end

  @impl true
  def handle_event("page", %{}, socket), do: noreply(socket)

  @impl true
  def handle_event(
        "apply-filter-search",
        %{"search_phrase" => search_phrase},
        socket
      ) do
    search_phrase = String.trim(search_phrase)

    search_phrase =
      if String.length(search_phrase) > 0, do: String.downcase(search_phrase), else: nil

    socket
    |> assign(search_phrase: search_phrase)
    |> reassign_pagination_and_finances()
  end

  @impl true
  def handle_event("clear-search", _, socket) do
    socket
    |> assign(:search_phrase, nil)
    |> reassign_pagination_and_finances()
  end

  @impl true
  def handle_event(
        "apply-filter-date-range",
        %{"dates" => %{"date_range" => date_range}},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      ) do
    if String.contains?(date_range, "to") do
      save_filters(organization_id, "finances", %{transaction_date_range: date_range})

      socket
      |> assign(transaction_date_range: date_range)
      |> split_and_assign_date_range(date_range)
      |> reassign_pagination_and_finances()
    else
      noreply(socket)
    end
  end

  @impl true
  def handle_event(
        "apply-filter-source",
        %{"option" => source},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      ) do
    save_filters(organization_id, "finances", %{transaction_source: source})

    socket
    |> assign(:transaction_source, source)
    |> reassign_pagination_and_finances()
  end

  @impl true
  def handle_event(
        "apply-filter-status",
        %{"option" => status},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      ) do
    save_filters(organization_id, "finances", %{transaction_status: status})

    socket
    |> assign(:transaction_status, status)
    |> reassign_pagination_and_finances()
  end

  @impl true
  def handle_event(
        "apply-filter-type",
        %{"option" => type},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      ) do
    save_filters(organization_id, "finances", %{transaction_type: type})

    socket
    |> assign(:transaction_type, type)
    |> reassign_pagination_and_finances()
  end

  @impl true
  def handle_event(
        "apply-filter-sort_by",
        %{"option" => sort_by},
        %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
      ) do
    sort_direction = Enum.find(sort_options(), fn op -> op.id == sort_by end).direction
    save_filters(organization_id, "finances", %{sort_by: sort_by, sort_direction: sort_direction})

    socket
    |> assign(:sort_by, sort_by)
    |> assign(:sort_col, Enum.find(sort_options(), fn op -> op.id == sort_by end).column)
    |> assign(:sort_direction, sort_direction)
    |> reassign_pagination_and_finances()
  end

  @impl true
  def handle_event(
        "sort_direction",
        _params,
        %{
          assigns: %{
            sort_direction: sort_direction,
            current_user: %{organization_id: organization_id}
          }
        } = socket
      ) do
    sort_direction = if(sort_direction == "asc", do: "desc", else: "asc")

    save_filters(organization_id, "finances", %{sort_direction: sort_direction})

    socket
    |> assign(:sort_direction, sort_direction)
    |> reassign_pagination_and_finances()
  end

  @impl true
  def handle_event("export-transactions", %{}, socket) do
    socket
    |> TodoplaceWeb.Live.FinancesManage.ExportTransactionsComponent.open()
    |> noreply()
  end

  @impl true
  def handle_event(
        "online-payment-view",
        %{"order_id" => id},
        %{assigns: %{current_user: %{organization: %{stripe_account_id: stripe_account_id}}}} =
          socket
      ) do
    order = Orders.get_order(id)

    socket
    |> OnlinePaymentViewComponent.open(%{
      transaction: order,
      stripe_account_id: stripe_account_id
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "online-payment-view",
        %{"payment_id" => id},
        %{assigns: %{current_user: %{organization: %{stripe_account_id: stripe_account_id}}}} =
          socket
      ) do
    payment_schedule = PaymentSchedules.get_payment_schedule(id)

    socket
    |> OnlinePaymentViewComponent.open(%{
      transaction: payment_schedule,
      stripe_account_id: stripe_account_id
    })
    |> noreply()
  end

  @impl true
  def render(assigns) do
    ~H"""
      <div class="pt-6 px-6 center-container flex flex-col" id="download-trigger" phx-hook="TriggerDownload">
        <div class="flex items-center">
          <h1 class="text-4xl font-bold">Finances</h1>
        </div>
        <div class="w-48 text-center text-blue-planning-300 pt-2 mt-4 font-bold border-b-4 border-blue-planning-300">
          Transactions Report
        </div>
      </div>
      <div class="bg-base-200 xl:py-7">
        <div class="center-container p-5">
          <div class="p-5 bg-white rounded-t-xl">
            <div class="flex flex-col justify-between md:flex-row">
              <div class="font-bold text-xl mb-7">
                All Transactions
              </div>
              <div class="flex items-center lg:w-1/2 xl:w-2/5 gap-3">
                <a phx-click="export-transactions" class="hidden btn-tertiary px-2 py-1 xl:flex items-center justify-center gap-2 text-blue-planning-300 xl:w-auto w-full h-11 text-center cursor-pointer">
                  <div class="flex items-end pb-3 xl:pb-0 mt-3 xl:mt-0 flex gap-2 items-center justify-center">
                    <.icon name="download" class="w-4 h-4 text-blue-planning-300 mt-0.5" />
                    Export
                  </div>
                </a>
                <div class="w-full">
                  <div class="relative">
                    <a {testid("close_search")} class="absolute top-0 bottom-0 flex flex-row items-center justify-center overflow-hidden text-xs text-gray-400 left-2">
                      <%= if @search_phrase do %>
                        <span phx-click="clear-search" class="cursor-pointer">
                          <.icon name="close-x" class="w-4 ml-1 fill-current stroke-current stroke-2 close-icon text-blue-planning-300" />
                        </span>
                      <% else %>
                        <.icon name="search" class="w-4 ml-1 fill-current" />
                      <% end %>
                    </a>
                    <.form for={%{}} as={:search} phx-change="apply-filter-search" phx-submit="apply-filter-search">
                      <input type="text" class="form-control w-full text-input indent-6 bg-base-200" id="search_phrase_input" name="search_phrase" value={@search_phrase} phx-debounce="500" spellcheck="false" placeholder="Search by client or transaction..." />
                    </.form>
                  </div>
                </div>
              </div>
            </div>
              <div class="xl:flex justify-between mt-4">
                <div class="grid grid-cols-2 sm:grid-cols-2 xl:flex gap-2">
                  <.form class="col-span-2 lg:col-span-1 xl:w-4/12" :let={f} for={%{}} as={:dates} phx-change="apply-filter-date-range">
                    <.date_range_picker_field class="relative flex flex-col col-span-3 sm:col-span-1 w-full mb-3 lg:mb-0" id="date_range" form={f} field={:date_range} default_date={@transaction_date_range} input_placeholder="mm/dd/yyyy to mm/dd/yyyy" input_label="Date Range" data_max_date="today" />
                  </.form>
                  <.select_dropdown class="xl:w-44" title="Type" id="type" selected_option={@transaction_type} options_list={%{"all" => "All", "job-retainer" => "Job-Retainer", "job-payment" => "Job-Payment", "gallery-order" => "Gallery-Order"}}/>
                  <.select_dropdown class="xl:w-44" title="Source" id="source" selected_option={@transaction_source} options_list={%{"all" => "All", "stripe" => "Stripe", "offline" => "Offline"}}/>
                  <.select_dropdown class="xl:w-44" title="Status" id="status" selected_option={@transaction_status} options_list={%{"all" => "All", "overdue" => "Overdue", "paid" => "Paid", "pending" => "Pending"}}/>
                  <.select_dropdown class="xl:w-44 col-span-1 sm:col-span-1" sort_direction={@sort_direction} title="Sort" id="sort_by" selected_option={@sort_by} options_list={%{"newest" => "Newest", "oldest" => "Oldest", "highest" => "Highest", "lowest" => "Lowest"}}/>
                </div>

                <a phx-click="export-transactions" class="btn-tertiary mt-3 xl:mt-7 px-2 py-1 flex xl:hidden items-center justify-center gap-2 text-blue-planning-300 xl:w-auto w-full h-10 text-center cursor-pointer">
                  <div class="flex items-end pb-3 xl:pb-0 mt-3 xl:mt-0 flex gap-2 items-center justify-center">
                    <.icon name="download" class="w-4 h-4 text-blue-planning-300 mt-0.5" />
                    Export
                  </div>
                </a>
              </div>
            <div class="hidden xl:grid border-b-4 mt-5 grid grid-cols-7 border-blue-planning-300 pb-1.5 font-bold">
              <div class="col-span-1">
                Transaction Date
              </div>
              <div class="">
                Total
              </div>
              <div class="">
                Client
              </div>
              <div class="">
                Type / Job
              </div>
              <div class="">
                Source
              </div>
              <div class="col-span-2">
                Status
              </div>
            </div>

            <%= for transaction <- @finances do %>
              <div id={"item-" <> transaction.type <> "-" <> Integer.to_string(transaction.id)}>
                <%= render_row(assigns, transaction) %>
              </div>
            <% end %>
          </div>
          <.pagination_component wrapper_class="bg-white rounded-b-xl" pagination_changeset={@pagination_changeset} limit_options={[12, 24, 36, 48]} />
        </div>
      </div>
    """
  end

  def select_dropdown(assigns) do
    assigns =
      assigns
      |> Enum.into(%{class: ""})

    ~H"""
      <div class={"flex flex-col w-full mb-3 lg:mb-0 #{@class}"}>
        <h1 class="font-extrabold text-sm flex flex-col whitespace-nowrap mb-1"><%= @title %></h1>
        <div class="flex h-11 w-full">
          <div id={@id} class={classes("relative w-full border-grey border p-2 cursor-pointer", %{"rounded-l-lg" => @id == "sort_by", "rounded-lg" => @id != "sort_by"})} data-offset-y="5" phx-hook="Select">
            <div {testid("dropdown_#{@id}")} class="flex flex-row items-center border-gray-700">
                <%= @options_list[@selected_option] %>
                <.icon name="down" class="w-3 h-3 ml-auto lg:mr-2 mr-1 stroke-current stroke-2 open-icon" />
                <.icon name="up" class="hidden w-3 h-3 ml-auto lg:mr-2 mr-1 stroke-current stroke-2 close-icon" />
            </div>
            <ul class={"absolute z-30 hidden mt-2 bg-white toggle rounded-md popover-content border border-base-200 w-full"}>
              <%= for {key, label} <- @options_list do %>
                <li id={key} target-class="toggle-it" parent-class="toggle" toggle-type="selected-active" phx-hook="ToggleSiblings"
                class="flex items-center py-1.5 hover:bg-blue-planning-100 hover:rounded-md" phx-click={"apply-filter-#{@id}"} phx-value-option={key}>
                  <button id={"btn-#{key}"} class={"pl-2"}><%= label %></button>
                  <%= if key == @selected_option do %>
                    <.icon name="tick" class="w-6 h-5 ml-auto mr-1 toggle-it text-green" />
                  <% end %>
                </li>
              <% end %>
            </ul>
          </div>
          <%= if @title == "Sort" do%>
            <div class="items-center flex border rounded-r-lg border-grey p-2">
              <button phx-click="sort_direction">
                <%= if @sort_direction == "asc" do %>
                  <.icon name="sort-vector-2" {testid("edit-link-button")} class="blue-planning-300 w-5 h-5" />
                <% else %>
                  <.icon name="sort-vector" {testid("edit-link-button")} class="blue-planning-300 w-5 h-5" />
                <% end %>
              </button>
            </div>
          <% end %>
        </div>
      </div>
    """
  end

  defp render_row(assigns, %Todoplace.PaymentSchedule{} = payment_schedule) do
    assigns = Enum.into(assigns, %{payment_schedule: payment_schedule})

    ~H"""
    <.payment_schedule_row transaction={@payment_schedule} {assigns} />
    """
  end

  defp render_row(assigns, %Todoplace.Cart.Order{} = gallery_order) do
    assigns = Enum.into(assigns, %{gallery_order: gallery_order})

    ~H"""
    <.gallery_order_row transaction={@gallery_order} {assigns} />
    """
  end

  defp payment_schedule_row(assigns) do
    ~H"""
    <div class="mt-3 xl:grid grid-cols-7 pb-1.5">
      <div class="sm:pr-1 col-span-1">
        <div class="font-bold"><b class="sm:hidden mr-2">Transaction Date:</b><%= Calendar.strftime(@transaction.updated_at, "%m/%d/%y") %></div>
      </div>
      <div class="flex sm:pr-1">
        <div class="text-base-250 mr-1"><b class="sm:hidden mr-2 text-black">Total:</b><%= @transaction.price %></div>
        <a phx-click="online-payment-view" phx-value-payment_id={@transaction.id}><.icon name="eye" class="w-4 h-4 mt-1 text-blue-planning-300 cursor-pointer"/></a>
      </div>
      <div class="text-blue-planning-300 sm:pr-1 hover:cursor-pointer capitalize break-words">
        <b class="sm:hidden mr-1 text-black">Client:</b>
        <a class="underline" href={~p"/clients/#{@transaction.job.client_id}"} target="_blank">
          <%= @transaction.job.client.name || "-" %>
        </a>
      </div>
      <div class="text-blue-planning-300 cursor-pointer sm:pr-1 break-words">
        <b class="sm:hidden mr-1 text-black">Type / Job:</b>
        <%= if @transaction.job.job_status.is_lead do %>
          <a class="underline" href={~p"/leads/#{@transaction.job_id}"} target="_blank">
            <%= @transaction.type %>
          </a>
        <% else %>
          <a class="underline" href={~p"/jobs/#{@transaction.job_id}"} target="_blank">
            <%= @transaction.type %>
          </a>
        <% end %>
        <div class="text-base-250"><%= Todoplace.Job.name(@transaction.job) %></div>
      </div>
      <div class="text-base-250 sm:pr-1">
        <b class="sm:hidden mr-2 text-black">Source:</b><%= @transaction.source %>
      </div>
      <div class="lg:flex justify-between sm:pr-1 col-span-2">
        <div class="">
            <.badge color={get_badge_color(@transaction.status)}><%= @transaction.status %></.badge>
        </div>
        <div class="mt-2 lg:mt-0">
          <div data-offset="0" phx-hook="Select" data-placement="bottom-end" id={"transaction-actions-#{@transaction.id}"}>
            <button {testid("actions")} title="Manage" class="btn-tertiary px-2 py-1 flex items-center gap-3 mr-2 text-blue-planning-300 xl:w-auto w-full">
              Actions
              <.icon name="down" class="w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 open-icon" />
              <.icon name="up" class="hidden w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 close-icon" />
            </button>
            <div class="flex flex-col hidden bg-white border rounded-lg shadow-lg popover-content" style="z-index: 2147483001;">
              <a href={~p"/jobs/#{@transaction.job_id}"} target="_blank" class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
                <.icon name="gallery-camera" class="inline-block w-4 h-4 mt-1 mr-2 text-blue-planning-300" />
                View job
              </a>
              <a href={~p"/clients/#{@transaction.job.client_id}"} target="_blank" class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
                <.icon name="client-icon" class="inline-block w-4 h-4 mt-1 mr-2 fill-current text-blue-planning-300" />
                View client
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
    <hr class="mr-4 my-3 col-span-6">
    """
  end

  defp gallery_order_row(assigns) do
    ~H"""
     <div class="mt-3 xl:grid grid-cols-7 pb-1.5">
      <div class="sm:pr-1">
        <div class="font-bold"><b class="sm:hidden mr-2">Transaction Date:</b><%= Calendar.strftime(@transaction.updated_at, "%m/%d/%y") %></div>
      </div>
      <div class="flex sm:pr-1">
        <div class="text-base-250 mr-1"><b class="sm:hidden mr-2 text-black">Total:</b><%= @transaction.price %></div>
        <a phx-click="online-payment-view" phx-value-order_id={@transaction.id}><.icon name="eye" class="w-4 h-4 mt-1 text-blue-planning-300 cursor-pointer"/></a>
      </div>
      <div class="text-blue-planning-300 sm:pr-1 hover:cursor-pointer capitalize break-words">
        <b class="sm:hidden mr-1 text-black">Client:</b>
        <a class="underline" href={~p"/clients/#{@transaction.client.id}"} target="_blank">
          <%= @transaction.gallery.job.client.name || "-" %>
        </a>
      </div>
      <div class="text-blue-planning-300 cursor-pointer sm:pr-1 break-words">
        <b class="sm:hidden mr-1 text-black">Type / Job:</b>
        <a class="underline" href={~p"/galleries/#{@transaction.gallery.id}/transactions/#{@transaction.number}"} target="_blank">
          <%= @transaction.type %>
        </a>
        <div class="text-base-250"><%= Todoplace.Job.name(@transaction.gallery.job) %></div>
      </div>
      <div class="text-base-250 sm:pr-1">
        <b class="sm:hidden mr-2 text-black">Source:</b><%= if(@transaction.source == "stripe", do: "Stripe", else: "Offline") %>
      </div>
      <div class="lg:flex justify-between sm:pr-1 col-span-2">
        <div class="">
            <.badge color={:green}>Paid</.badge>
        </div>
        <div class="mt-2 lg:mt-0">
          <div data-offset="0" data-placement="bottom-end" phx-hook="Select" id={"transaction-actions-#{@transaction.id}"}>
            <button {testid("actions")} title="Manage" class="btn-tertiary px-2 py-1 flex items-center gap-3 mr-2 text-blue-planning-300 xl:w-auto w-full">
              Actions
              <.icon name="down" class="w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 open-icon" />
              <.icon name="up" class="hidden w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 close-icon" />
            </button>
            <div class="flex flex-col hidden bg-white border rounded-lg shadow-lg popover-content" style="z-index: 2147483001;">
              <%= if @transaction.number do %>
                <a href={~p"/galleries/#{@transaction.gallery.id}/transactions/#{@transaction.number}"} target="_blank" class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
                  <.icon name="cart" class="inline-block w-4 h-4 mt-1 mr-2 text-blue-planning-300" />
                  View order details
                </a>
              <% end %>
              <a href={~p"/galleries/#{@transaction.gallery.id}"} target="_blank" class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
                <.icon name="photos-2" class="inline-block w-4 h-4 mt-1 mr-2 text-blue-planning-300" />
                View gallery
              </a>
              <a href={~p"/clients/#{@transaction.client.id}"} target="_blank" class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
                <.icon name="client-icon" class="inline-block w-4 h-4 mt-1 mr-2 fill-current text-blue-planning-300" />
                View client
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
    <hr class="mr-4 my-3 col-span-6">
    """
  end

  defp assign_finances(socket) do
    socket
    |> assign_preferred_filters()
    |> assign(:search_phrase, nil)
    |> fetch_finances()
  end

  defp assign_preferred_filters(
         %{assigns: %{current_user: %{organization_id: organization_id}}} = socket
       ) do
    case PreferredFilter.load_preferred_filters(organization_id, "finances") do
      %{
        filters: %{
          transaction_date_range: transaction_date_range,
          transaction_type: transaction_type,
          transaction_status: transaction_status,
          transaction_source: transaction_source,
          sort_by: sort_by,
          sort_direction: sort_direction
        }
      } ->
        socket
        |> assign_default_filters(
          transaction_date_range,
          transaction_status,
          transaction_source,
          transaction_type,
          sort_by,
          sort_direction
        )
        |> assign_sort_col(sort_by, "updated_at")

      _ ->
        socket
        |> assign_default_filters(get_initial_date_range(), "all", "all", "all", "newest", "asc")
    end
  end

  defp assign_sort_col(socket, nil, default_sort_col),
    do: assign(socket, :sort_col, default_sort_col)

  defp assign_sort_col(socket, sort_by, _default_sort_col),
    do: assign(socket, :sort_col, Enum.find(sort_options(), fn op -> op.id == sort_by end).column)

  defp assign_default_filters(
         socket,
         transaction_date_range,
         transaction_status,
         transaction_source,
         transaction_type,
         sort_by,
         sort_direction
       ) do
    socket
    |> assign(:transaction_date_range, transaction_date_range || get_initial_date_range())
    |> split_and_assign_date_range(transaction_date_range || get_initial_date_range())
    |> assign(:transaction_status, transaction_status || "all")
    |> assign(:transaction_source, transaction_source || "all")
    |> assign(:transaction_type, transaction_type || "all")
    |> assign(:sort_by, sort_by || "newest")
    |> assign(:sort_direction, sort_direction || "asc")
    |> assign_sort_col(sort_by, "updated_at")
  end

  defp get_initial_date_range() do
    current_date = Date.utc_today()
    # Three months ago
    start_date = Timex.shift(current_date, months: -3)

    "#{Date.to_iso8601(start_date)} to #{Date.to_iso8601(current_date)}"
  end

  defp reassign_pagination_and_finances(%{assigns: %{pagination_changeset: changeset}} = socket) do
    limit = pagination_index(changeset, :limit)

    socket
    |> reset_pagination(%{limit: limit, last_index: limit})
    |> fetch_finances()
    |> noreply()
  end

  defp fetch_finances(
         %{
           assigns: %{
             pagination_changeset: pagination_changeset,
             sort_col: sort_col,
             sort_direction: sort_direction
           }
         } = socket
       ) do
    pagination = pagination_changeset |> Changeset.apply_changes()

    finances = get_galleries_orders(socket.assigns) ++ get_payment_schedules(socket.assigns)
    sorted_finances = apply_sort(finances, sort_col, sort_direction)

    finances = apply_pagination(sorted_finances, pagination)

    socket
    |> assign(finances: finances)
    |> update_pagination(%{
      total_count:
        if(pagination.total_count == 0,
          do: Enum.count(sorted_finances),
          else: pagination.total_count
        ),
      last_index: pagination.first_index + Enum.count(finances) - 1
    })
  end

  defp apply_pagination(data, %{first_index: first_index, limit: limit}) do
    Enum.slice(data, first_index - 1, limit)
  end

  defp get_badge_color("Pending"), do: :blue
  defp get_badge_color("Overdue"), do: :red
  defp get_badge_color(_), do: :green
end
