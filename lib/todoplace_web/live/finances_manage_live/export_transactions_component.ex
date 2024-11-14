defmodule TodoplaceWeb.Live.FinancesManage.ExportTransactionsComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  import TodoplaceWeb.Live.FinancesManage.Shared,
    only: [
      split_and_assign_date_range: 2,
      get_galleries_orders: 1,
      get_payment_schedules: 1,
      sort_options: 0,
      apply_sort: 3
    ]

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(include_stripe: "true")
    |> assign(search_phrase: nil)
    |> assign(loading: false)
    |> assign(disable_export: false)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col w-80 modal-small p-30 text-black">
    <%= if @loading do %>
      <div class="text-3xl mb-4 font-bold flex justify-center">Export Transactions CSV</div>
      <div class="flex gap-2 items-center justify-center p-1 bg-white rounded-full">
        <.icon class="animate-spin w-5 h-5 text-blue-planning-300" name="loader"/>
        <p class="text-base-250 font-bold text-center">Generating Export</p>
      </div>
    <% else %>
      <div class="flex items-start justify-between flex-shrink-0">
        <div class="mb-4">
          <div class="text-3xl font-bold">Export Transactions CSV</div>
          <div class="text-base-250 mt-1.5">Select your parameters  for your export</div>
        </div>

        <button phx-click="modal" phx-value-action="close" title="close modal" type="button" class="p-2">
          <.icon name="close-x" class="w-3 h-3 stroke-current stroke-2 sm:stroke-1 sm:w-6 sm:h-6"/>
        </button>
      </div>

      <.form :let={f} for={%{}} as={:dates} phx-change="apply-filter-date-range" phx-target={@myself} class="flex flex-col gap-1">
          <.date_range_picker_field class="relative flex flex-col col-span-3 sm:col-span-1 w-full xl:w-full mb-3 lg:mb-0 pt-1" id="date_range" form={f} field={:date_range} default_date={@transaction_date_range} input_placeholder="mm/dd/yyyy to mm/dd/yyyy" input_label="Date Range" data_max_date="today" />
      </.form>
      <.select_dropdown myself={@myself} title="Type" id="type" selected_option={@transaction_type} options_list={%{"all" => "All", "job-retainer" => "Job-Retainer", "job-payment" => "Job-Payment", "gallery-order" => "Gallery-Order"}}/>
      <.select_dropdown myself={@myself} title="Source" id="source" selected_option={@transaction_source} options_list={%{"all" => "All", "stripe" => "Stripe", "offline" => "Offline"}}/>
      <.select_dropdown myself={@myself} title="Status" id="status" selected_option={@transaction_status} options_list={%{"all" => "All", "overdue" => "Overdue", "paid" => "Paid", "pending" => "Pending"}}/>
      <.select_dropdown myself={@myself} class="col-span-2 sm:col-span-1" sort_direction={@sort_direction} title="Sort" id="sort_by" selected_option={@sort_by} options_list={%{"newest" => "Newest", "oldest" => "Oldest", "highest" => "Highest", "lowest" => "Lowest"}}/>
      <div class=" flex gap-2 my-3">
      <.form :let={f} for={%{}} phx-change="toggle_include_stripe" phx-target={@myself}>
        <%= input f, :include_stripe, type: :checkbox, checked: true, class: "checkbox w-5 h-5 mb-1 cursor-pointer border-blue-planning-300"%>
      </.form>
        <div>
          <p class="font-bold">Include Stripe details</p>
          <p class="text-base-250">This will capture taxes and fees if applicable
          (Note: export may take longer)</p>
        </div>
      </div>
      <button phx-click="export_csv" phx-target={@myself} type="button" disabled={@disable_export} class="btn-primary my-3">Start Export</button>
      <button phx-click="modal" phx-value-action="close" title="close modal" type="button" class="btn-secondary text-black">Cancel</button>
      <% end %>
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
                class="flex items-center py-1.5 hover:bg-blue-planning-100 hover:rounded-md" phx-click={"apply-filter-#{@id}"} phx-target={@myself} phx-value-option={key}>
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
              <button phx-click="sort_direction" phx-target={@myself}>
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

  def open(%{assigns: assigns} = socket),
    do: socket |> open_modal(__MODULE__, %{assigns: assigns |> Map.drop([:flash])})

  @impl true
  def handle_event("toggle_include_stripe", %{"include_stripe" => include_stripe}, socket) do
    socket
    |> assign(include_stripe: include_stripe)
    |> noreply()
  end

  @impl true
  def handle_event("apply-filter-date-range", %{"dates" => %{"date_range" => date_range}}, socket) do
    if String.contains?(date_range, " to ") do
      socket
      |> assign(transaction_date_range: date_range)
      |> assign(disable_export: false)
      |> split_and_assign_date_range(date_range)
      |> noreply()
    else
      socket
      |> assign(disable_export: true)
      |> noreply()
    end
  end

  @impl true
  def handle_event("apply-filter-source", %{"option" => source}, socket) do
    socket |> assign(:transaction_source, source) |> noreply()
  end

  @impl true
  def handle_event("apply-filter-status", %{"option" => status}, socket) do
    socket |> assign(:transaction_status, status) |> noreply()
  end

  @impl true
  def handle_event("apply-filter-type", %{"option" => type}, socket) do
    socket |> assign(:transaction_type, type) |> noreply()
  end

  @impl true
  def handle_event(
        "apply-filter-sort_by",
        %{"option" => sort_by},
        %{assigns: %{current_user: %{organization_id: _organization_id}}} = socket
      ) do
    socket
    |> assign(:sort_by, sort_by)
    |> assign(:sort_col, Enum.find(sort_options(), fn op -> op.id == sort_by end).column)
    |> assign(
      :sort_direction,
      Enum.find(sort_options(), fn op -> op.id == sort_by end).direction
    )
    |> noreply()
  end

  @impl true
  def handle_event(
        "sort_direction",
        _params,
        %{
          assigns: %{
            sort_direction: sort_direction,
            current_user: %{organization_id: _organization_id}
          }
        } = socket
      ) do
    sort_direction = if(sort_direction == "asc", do: "desc", else: "asc")

    socket
    |> assign(:sort_direction, sort_direction)
    |> noreply()
  end

  @impl true
  def handle_event(
        "export_csv",
        _params,
        %{assigns: %{transaction_date_range: date_range}} = socket
      ) do
    pid = self()

    # Start a separate process for CSV generation
    Task.start(fn ->
      signed_at = DateTime.utc_now() |> DateTime.to_unix()

      token =
        Phoenix.Token.sign(TodoplaceWeb.Endpoint, "CSV-filename", date_range, signed_at: signed_at)

      csv_data = generate_csv_data(socket)
      file_path = save_csv_file(csv_data, date_range)

      if is_binary(file_path) do
        # Generate a download URL
        download_url = ~p"/finance-export/csv/#{token}"

        # Push event to trigger download
        send(pid, {:csv_export_done, download_url})
      else
        # Handle file generation failure
        send(pid, :csv_export_failed)
      end
    end)

    socket
    # Set loading to true immediately and update the socket
    |> assign(:loading, true)
    |> noreply()
  end

  @headers [
    "Transaction Date",
    "Total",
    "Client",
    "Job Name/Title",
    "Type",
    "Source",
    "Status",
    "Tax"
  ]
  defp generate_csv_data(socket) do
    socket
    |> fetch_finances()
    |> Enum.map(fn transaction ->
      [
        get_transaction_date(transaction.updated_at),
        transaction.price,
        get_client_name(transaction),
        get_job_name(transaction),
        transaction.type,
        transaction.source,
        transaction.status
      ] ++
        if(socket.assigns.include_stripe == "true" && transaction.source == "Stripe",
          do: [assign_tax_amount(socket, transaction)],
          else: []
        )
    end)
    |> then(&[@headers | &1])
    |> CSV.encode()
    |> Enum.to_list()
    |> to_string()
  end

  defp get_job_name(%Todoplace.PaymentSchedule{} = transaction),
    do: Todoplace.Job.name(transaction.job)

  defp get_job_name(%Todoplace.Cart.Order{} = transaction),
    do: Todoplace.Job.name(transaction.gallery.job)

  defp get_transaction_date(date), do: date |> format_date_via_type("MM/DD/YY")

  defp get_client_name(%Todoplace.PaymentSchedule{} = transaction), do: transaction.job.client.name

  defp get_client_name(%Todoplace.Cart.Order{} = transaction),
    do: transaction.gallery.job.client.name

  defp save_csv_file(csv_data, date_range) do
    # Define a directory for temporary files
    # Ensure this directory exists and is writable by the application
    temp_dir = "tmp/csv_exports"
    File.mkdir_p(temp_dir)

    # Generate a unique file name
    file_name = "#{date_range}.csv"
    file_path = Path.join(temp_dir, file_name)

    # Write the CSV data to the file
    case File.write(file_path, csv_data) do
      :ok ->
        file_path

      {:error, reason} ->
        IO.warn("Failed to write CSV file: #{reason}")
        nil
    end
  end

  defp fetch_finances(%{assigns: %{transaction_date_range: date_range}} = socket) do
    socket
    |> split_and_assign_date_range(date_range)
    |> then(fn %{assigns: assigns} ->
      (get_galleries_orders(assigns) ++ get_payment_schedules(assigns))
      |> apply_sort(assigns.sort_col, assigns.sort_direction)
    end)
  end

  defp assign_tax_amount(
         socket,
         %{intent: %{stripe_session_id: stripe_session_id}}
       )
       when not is_nil(stripe_session_id),
       do: retrieve_tax_amount(socket, stripe_session_id)

  defp assign_tax_amount(_, _), do: 0

  defp retrieve_tax_amount(
         %{assigns: %{current_user: %{organization: %{stripe_account_id: stripe_account_id}}}},
         stripe_session_id
       ) do
    case Todoplace.Payments.retrieve_session(stripe_session_id, connect_account: stripe_account_id) do
      {:ok, session} -> session.total_details.amount_tax
      {:error, _} -> 0
    end
  end
end
