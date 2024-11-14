defmodule TodoplaceWeb.JobLive.Index do
  @moduledoc false
  use TodoplaceWeb, :live_view

  import TodoplaceWeb.JobLive.Shared, only: [status_badge: 1]

  import TodoplaceWeb.Shared.CustomPagination,
    only: [
      pagination_component: 1,
      assign_pagination: 2,
      update_pagination: 2,
      reset_pagination: 2,
      pagination_index: 2
    ]

  import TodoplaceWeb.Live.Shared, only: [save_filters: 3]

  alias Ecto.Changeset
  alias Todoplace.{Job, Jobs, Repo, Payments, Package, PreferredFilter, Utils}
  alias TodoplaceWeb.{JobLive}

  @default_pagination_limit 12

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(collapsed_shoots: [])
    |> assign_defaults()
    |> assign_stripe_status()
    |> ok()
  end

  @impl true
  def handle_event(
        "toggle-shoots",
        %{"job_id" => job_id},
        %{assigns: %{collapsed_shoots: collapsed_shoots}} = socket
      ) do
    job_id = String.to_integer(job_id)

    collapsed_shoots =
      if Enum.member?(collapsed_shoots, job_id) do
        Enum.filter(collapsed_shoots, &(&1 != job_id))
      else
        collapsed_shoots ++ [job_id]
      end

    socket
    |> assign(:collapsed_shoots, collapsed_shoots)
    |> noreply()
  end

  @impl true
  def handle_event(
        "apply-filter-status",
        %{"option" => status},
        %{assigns: %{live_action: live_action, current_user: %{organization_id: organization_id}}} =
          socket
      ) do
    save_preferred_filters(live_action, organization_id, %{job_status: status})

    socket
    |> assign(:job_status, status)
    |> reassign_pagination_and_jobs()
  end

  @impl true
  def handle_event(
        "apply-filter-type",
        %{"option" => type},
        %{assigns: %{live_action: live_action, current_user: %{organization_id: organization_id}}} =
          socket
      ) do
    save_preferred_filters(live_action, organization_id, %{job_type: type})

    socket
    |> assign(:job_type, type)
    |> reassign_pagination_and_jobs()
  end

  @impl true
  def handle_event(
        "apply-filter-sort_by",
        %{"option" => sort_by},
        %{assigns: %{live_action: live_action, current_user: %{organization_id: organization_id}}} =
          socket
      ) do
    save_preferred_filters(live_action, organization_id, %{sort_by: sort_by})

    socket
    |> assign(:sort_by, sort_by)
    |> assign(
      :sort_col,
      if(sort_by in ["oldest_lead", "newest_lead"],
        do: Enum.find(lead_sort_options(), fn op -> op.id == sort_by end).column,
        else: Enum.find(job_sort_options(), fn op -> op.id == sort_by end).column
      )
    )
    |> assign(
      :sort_direction,
      if(sort_by in ["oldest_job", "oldest_lead"], do: :asc, else: :desc)
    )
    |> reassign_pagination_and_jobs()
  end

  @impl true
  def handle_event(
        "toggle-sort-direction",
        _,
        %{
          assigns: %{
            sort_direction: sort_direction,
            live_action: live_action,
            current_user: %{organization_id: organization_id}
          }
        } = socket
      ) do
    sort_direction = if(sort_direction == :asc, do: :desc, else: :asc)

    save_preferred_filters(live_action, organization_id, %{
      sort_direction: to_string(sort_direction)
    })

    socket
    |> assign(:sort_direction, sort_direction)
    |> reassign_pagination_and_jobs()
  end

  @impl true
  def handle_event(
        "search",
        %{"search_phrase" => search_phrase},
        socket
      ) do
    search_phrase = String.trim(search_phrase)

    search_phrase =
      if String.length(search_phrase) > 0, do: String.downcase(search_phrase), else: nil

    socket
    |> assign(search_phrase: search_phrase)
    |> reassign_pagination_and_jobs()
  end

  @impl true
  def handle_event("clear-search", _, socket) do
    socket
    |> assign(:search_phrase, nil)
    |> reassign_pagination_and_jobs()
  end

  @impl true
  def handle_event("view-job", %{"id" => id}, %{assigns: %{type: type}} = socket) do
    socket
    |> push_redirect(to: ~p"/#{if String.to_atom(type.plural) == :leads, do: "leads", else: "jobs"}/#{id}")
    |> noreply()
  end

  @impl true
  def handle_event("view-client", %{"id" => id}, %{assigns: %{jobs: jobs}} = socket) do
    job = jobs |> Enum.find(&(&1.id == to_integer(id)))

    socket
    |> push_redirect(to: ~p"/clients/#{job.client_id}")
    |> noreply()
  end

  @impl true
  def handle_event("view-galleries", %{"id" => id}, %{assigns: %{type: type}} = socket) do
    socket
    |> push_redirect(
      to: ~p"/#{if String.to_atom(type.plural) == :leads, do: "leads", else: "jobs"}/#{id}?#{%{tab_active: "galleries"}}"
    )
    |> noreply()
  end

  @impl true
  def handle_event("create-lead", %{}, %{assigns: %{current_user: current_user}} = socket),
    do:
      socket
      |> open_modal(
        TodoplaceWeb.JobLive.NewComponent,
        %{current_user: current_user}
      )
      |> noreply()

  @impl true
  def handle_event("import-job", %{}, socket),
    do:
      socket
      |> open_modal(TodoplaceWeb.JobLive.ImportWizard, Map.take(socket.assigns, [:current_user]))
      |> noreply()

  @impl true
  def handle_event(
        "page",
        %{"direction" => _direction} = params,
        socket
      ) do
    socket
    |> update_pagination(params)
    |> assign_jobs()
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
    |> assign_jobs()
    |> noreply()
  end

  @impl true
  def handle_event("page", %{}, socket), do: socket |> noreply()

  @impl true
  def handle_event("intro_js" = event, params, socket),
    do: TodoplaceWeb.LiveHelpers.handle_event(event, params, socket)

  defdelegate handle_event(event, params, socket), to: JobLive.Shared

  @impl true
  def handle_info({:stripe_status, status}, socket) do
    socket |> assign(stripe_status: status) |> noreply()
  end

  defdelegate handle_info(message, socket), to: JobLive.Shared

  def actions(assigns) do
    ~H"""
    <div class="flex items-center md:ml-auto w-full md:w-auto left-3 sm:left-8" data-offset="0" phx-update="ignore" data-placement="bottom-end" phx-hook="Select" id={"manage-job-#{@job.id}"}>
      <button title="Manage" class="btn-tertiary px-2 py-1 flex items-center gap-3 mr-2 text-blue-planning-300 xl:w-auto w-full">
        Actions
        <.icon name="down" class="w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 open-icon" />
        <.icon name="up" class="hidden w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 close-icon" />
      </button>

      <div class="z-10 flex flex-col hidden w-44 bg-white border rounded-lg shadow-lg popover-content">
        <%= for %{title: title, action: action, icon: icon} <- actions(), (@type.plural == "jobs") || (@type.plural == "leads" and action not in ["complete-job", "view-galleries"]) do %>
          <button title={title} type="button" phx-click={action} phx-value-id={@job.id} class={classes("flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100", %{"hidden" => hide_action?(@job, icon)})}>
            <.icon name={icon} class={classes("inline-block w-4 h-4 mr-3 fill-current", %{"text-red-sales-300" => icon == "trash", "text-blue-planning-300" => icon != "trash"})} />
            <%= title %>
          </button>
        <% end %>
        <%= if @job.job_status.current_status == :archived do %>
            <button title="Unarchive" type="button" phx-click="confirm-archive-unarchive" phx-value-id={@job.id} class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100">
              <.icon name="plus" class="inline-block w-4 h-4 mr-3 text-blue-planning-300" />
              Unarchive
            </button>
        <% end %>
      </div>
    </div>
    """
  end

  def card_date(:jobs, "" <> time_zone, %Job{shoots: shoots}) do
    try do
      date =
        shoots
        |> Enum.map(& &1.starts_at)
        |> Enum.filter(&(DateTime.compare(&1, DateTime.utc_now()) == :gt))
        |> Enum.min(DateTime)

      strftime(time_zone, date, "%B %d, %Y @ %I:%M %p")
    rescue
      _e in Enum.EmptyError ->
        nil
    end
  end

  def card_date(:leads, _, _), do: nil

  def select_dropdown(assigns) do
    assigns =
      assigns
      |> Enum.into(%{class: ""})

    ~H"""
      <div class="flex flex-col w-full lg:w-auto mr-2 mb-3 lg:mb-0">
        <h1 class="font-extrabold text-sm flex flex-col whitespace-nowrap mb-1"><%= @title %></h1>
        <div class="flex">
          <div id={@id} class={classes("relative w-full lg:w-48 border-grey border p-2 cursor-pointer", %{"lg:w-64" => @id == "status" and @type == "lead", "rounded-l-lg" => @id == "sort_by", "rounded-lg" => @title == "Filter" or @id != "sort_by"})} data-offset-y="5" phx-hook="Select">
            <div {testid("dropdown_#{@id}")} class="flex flex-row items-center border-gray-700">
                <%= Utils.capitalize_per_word(String.replace(@selected_option, "_", " ")) %>
                <.icon name="down" class="w-3 h-3 ml-auto lg:mr-2 mr-1 stroke-current stroke-2 open-icon" />
                <.icon name="up" class="hidden w-3 h-3 ml-auto lg:mr-2 mr-1 stroke-current stroke-2 close-icon" />
            </div>
            <ul class={"absolute z-30 hidden mt-2 bg-white toggle rounded-md popover-content border border-base-200 #{@class}"}>
              <%= for option <- @options_list do %>
                <li id={option.id} target-class="toggle-it" parent-class="toggle" toggle-type="selected-active" phx-hook="ToggleSiblings"
                class="flex items-center py-1.5 hover:bg-blue-planning-100 hover:rounded-md" phx-click={"apply-filter-#{@id}"} phx-value-option={option.id}>
                  <button id={"btn-#{option.id}"} class={classes("album-select", %{"w-64" => @id == "status", "w-40" => @id != "status"})}><%= option.title %></button>
                  <%= if option.id == @selected_option do %>
                    <.icon name="tick" class="w-6 h-5 ml-auto mr-1 toggle-it text-green" />
                  <% end %>
                </li>
              <% end %>
            </ul>
          </div>
          <%= if @title == "Sort" do%>
            <div class="items-center flex border rounded-r-lg border-grey p-2">
              <button phx-click="toggle-sort-direction" disabled={@selected_option not in ["name", "shoot_date"]}>
                <%= if @sort_direction == :asc do %>
                  <.icon name="sort-vector-2" {testid("edit-link-button")} class={classes("blue-planning-300 w-5 h-5", %{"pointer-events-none opacity-40" => @selected_option not in ["name", "shoot_date"]})} />
                <% else %>
                  <.icon name="sort-vector" {testid("edit-link-button")} class={classes("blue-planning-300 w-5 h-5", %{"pointer-events-none opacity-40" => @selected_option not in ["name", "shoot_date"]})} />
                <% end %>
              </button>
            </div>
          <% end %>
        </div>
      </div>
    """
  end

  def search_sort_bar(assigns) do
    ~H"""
      <div {testid("search_filter_and_sort_bar")} class="flex flex-col px-5 center-container justify-between items-end px-1.5 lg:flex-row mb-0 md:mb-10">
        <div class="relative flex w-full lg:w-2/3 mr-2 mb-3 md:mb-0">
          <a {testid("close_search")} class="absolute top-0 bottom-0 flex flex-row items-center justify-center overflow-hidden text-xs text-gray-400 left-2">
            <%= if @search_phrase do %>
              <span phx-click="clear-search" class="cursor-pointer">
                <.icon name="close-x" class="w-4 ml-1 fill-current stroke-current stroke-2 close-icon text-blue-planning-300" />
              </span>
            <% else %>
              <.icon name="search" class="w-4 ml-1 fill-current" />
            <% end %>
          </a>
          <%= form_tag("#", [phx_change: :search, phx_submit: :submit, class: "w-full"]) do %>
            <input disabled={!is_nil(@selected_job)} type="text" class="form-control w-full lg:w-64 text-input indent-6 bg-base-200" id="search_phrase_input" name="search_phrase" value={"#{@search_phrase}"} phx-debounce="100" spellcheck="false" placeholder={@placeholder} />
          <% end %>
        </div>
        <.select_dropdown class="w-full md:w-60" type={@type} title={if @type == "job", do: 'Job Status', else: 'Lead Status'} id="status" selected_option={@job_status} options_list={if @type == "job", do: job_status_options(), else: lead_status_options()}/>

        <.select_dropdown class="w-full" title={if @type == "job", do: 'Job Type', else: 'Lead Type'} id="type" selected_option={@job_type} options_list={job_type_options(@job_types)}/>

        <.select_dropdown class="w-full" sort_direction={@sort_direction} title="Sort" id="sort_by" selected_option={@sort_by} options_list={if @type == "job", do: job_sort_options(), else: lead_sort_options()}/>

      </div>
    """
  end

  defp save_preferred_filters(live_action, organization_id, filter) do
    case live_action do
      :leads ->
        save_filters(organization_id, "leads", filter)

      :jobs ->
        save_filters(organization_id, "jobs", filter)
    end
  end

  defp assign_stripe_status(%{assigns: %{current_user: current_user}} = socket) do
    socket |> assign(stripe_status: Payments.status(current_user))
  end

  defp reassign_pagination_and_jobs(%{assigns: %{pagination_changeset: changeset}} = socket) do
    limit = pagination_index(changeset, :limit)

    socket
    |> reset_pagination(%{limit: limit, last_index: limit, total_count: job_count(socket)})
    |> assign_jobs()
    |> noreply()
  end

  defp assign_jobs(
         %{
           assigns: %{
             current_user: current_user,
             type: type,
             job_status: status,
             job_type: job_type,
             sort_col: sort_by,
             sort_direction: sort_direction,
             search_phrase: search_phrase,
             pagination_changeset: pagination_changeset
           }
         } = socket
       ) do
    pagination = pagination_changeset |> Changeset.apply_changes()

    jobs =
      current_user
      |> Job.for_user()
      |> process_query(type)
      |> Jobs.get_jobs_by_pagination(
        %{
          status: status,
          type: job_type,
          sort_by: sort_by,
          sort_direction: sort_direction,
          search_phrase: search_phrase
        },
        pagination: pagination
      )
      |> Repo.all()

    socket
    |> assign(jobs: jobs)
    |> update_pagination(%{
      total_count:
        if(pagination.total_count == 0,
          do: job_count(socket),
          else: pagination.total_count
        ),
      last_index: pagination.first_index + Enum.count(jobs) - 1
    })
  end

  defp process_query(query, %{plural: "leads"}), do: query |> Job.leads()
  defp process_query(query, %{plural: "jobs"}), do: query |> Job.not_leads()

  defp job_count(%{
         assigns: %{
           type: type,
           current_user: user,
           job_status: status,
           job_type: job_type,
           sort_col: sort_by,
           sort_direction: sort_direction,
           search_phrase: search_phrase
         }
       }) do
    user
    |> Job.for_user()
    |> process_query(type)
    |> Jobs.get_jobs(%{
      status: status,
      type: job_type,
      sort_by: sort_by,
      sort_direction: sort_direction,
      search_phrase: search_phrase
    })
    |> Jobs.count()
  end

  defp assign_defaults(socket) do
    socket
    |> assign_search()
    |> assign_pagination(@default_pagination_limit)
    |> assign(current_focus: -1)
    |> assign(:job_types, Todoplace.JobType.all())
    |> assign_new(:selected_job, fn -> nil end)
    |> assign_type_strings()
    |> assign_filters()
    |> then(fn socket -> assign_jobs(socket) end)
  end

  defp assign_filters(
         %{assigns: %{live_action: :jobs, current_user: %{organization_id: organization_id}}} =
           socket
       ) do
    case PreferredFilter.load_preferred_filters(organization_id, "jobs") do
      %{
        filters: filters
      } ->
        loaded_filters(
          socket,
          filters,
          "shoot_date",
          :starts_at
        )

      _ ->
        default_filters(socket, "shoot_date", :starts_at)
    end
  end

  defp assign_filters(
         %{assigns: %{live_action: :leads, current_user: %{organization_id: organization_id}}} =
           socket
       ) do
    case PreferredFilter.load_preferred_filters(organization_id, "leads") do
      %{
        filters: filters
      } ->
        loaded_filters(
          socket,
          filters,
          "newest_lead",
          :inserted_at
        )

      _ ->
        default_filters(socket, "newest_lead", :inserted_at)
    end
  end

  defp loaded_filters(
         socket,
         %{
           sort_by: sort_by,
           job_type: job_type,
           job_status: job_status,
           sort_direction: sort_direction
         },
         default_sort_by,
         default_sort_col
       ) do
    socket
    |> assign_default_filters(job_status, job_type)
    |> assign(:sort_by, sort_by || default_sort_by)
    |> assign_sort_col(sort_by, default_sort_col)
    |> assign_sort_direction(sort_by, sort_direction)
  end

  defp assign_sort_col(socket, nil, default_sort_col),
    do: socket |> assign(:sort_col, default_sort_col)

  defp assign_sort_col(socket, sort_by, _default_sort_by),
    do:
      socket
      |> assign(
        :sort_col,
        if(sort_by in ["oldest_lead", "newest_lead"],
          do: Enum.find(lead_sort_options(), fn op -> op.id == sort_by end).column,
          else: Enum.find(job_sort_options(), fn op -> op.id == sort_by end).column
        )
      )

  defp assign_sort_direction(socket, nil, sort_direction) when not is_nil(sort_direction),
    do: socket |> assign(:sort_direction, String.to_atom(sort_direction))

  defp assign_sort_direction(socket, nil, _sort_direction),
    do: socket |> assign(:sort_direction, :desc)

  defp assign_sort_direction(socket, sort_by, _sort_direction)
       when sort_by in ["oldest_job", "oldest_lead"],
       do:
         socket
         |> assign(:sort_direction, :asc)

  defp assign_sort_direction(socket, sort_by, _sort_direction)
       when sort_by in ["newest_job", "newest_lead"],
       do:
         socket
         |> assign(:sort_direction, :desc)

  defp assign_sort_direction(socket, _sort_by, nil),
    do:
      socket
      |> assign(:sort_direction, :desc)

  defp assign_sort_direction(socket, _sort_by, sort_direction),
    do:
      socket
      |> assign(:sort_direction, String.to_atom(sort_direction))

  defp default_filters(socket, sort_by, sort_col) do
    socket
    |> assign_default_filters("all", "all")
    |> assign(:sort_by, sort_by)
    |> assign(:sort_direction, :desc)
    |> assign(:sort_col, sort_col)
  end

  defp assign_default_filters(socket, job_status, job_type),
    do:
      socket
      |> assign(:job_status, job_status || "all")
      |> assign(:job_type, job_type || "all")

  defp assign_type_strings(%{assigns: %{live_action: live_action}} = socket) do
    if live_action == :jobs,
      do:
        socket
        |> assign(:type, %{singular: "job", plural: "jobs"}),
      else:
        socket
        |> assign(:type, %{singular: "lead", plural: "leads"})
  end

  defp assign_search(socket) do
    socket
    |> assign(:search_results, [])
    |> assign(:search_phrase, nil)
    |> assign(:searched_job, nil)
  end

  defp job_status_options do
    [
      %{title: "All", id: "all"},
      %{title: "Active", id: "active"},
      %{title: "Overdue", id: "overdue"},
      %{title: "Completed", id: "completed"},
      %{title: "Archived", id: "archived"}
    ]
  end

  defp lead_status_options do
    [
      %{title: "All", id: "all"},
      %{title: "Active Leads", id: "active_leads"},
      %{title: "Archived Leads", id: "archived_leads"},
      %{title: "Pending Invoice", id: "pending_invoice"},
      %{title: "Awaiting Questionnaire", id: "awaiting_questionnaire"},
      %{title: "Awaiting Contract", id: "awaiting_contract"},
      %{title: "New", id: "new"}
    ]
  end

  def job_type_options(job_types) do
    types =
      job_types
      |> Enum.map(fn type -> %{title: String.capitalize(type), id: type} end)

    [%{title: "All", id: "all"} | types]
  end

  defp job_sort_options do
    [
      %{title: "Name", id: "name", column: :name, direction: :desc},
      %{title: "Oldest Job", id: "oldest_job", column: :inserted_at, direction: :asc},
      %{title: "Newest Job", id: "newest_job", column: :inserted_at, direction: :desc},
      %{title: "Shoot Date", id: "shoot_date", column: :starts_at, direction: :desc}
    ]
  end

  defp lead_sort_options do
    [
      %{title: "Name", id: "name", column: :name, direction: :desc},
      %{title: "Oldest Lead", id: "oldest_lead", column: :inserted_at, direction: :asc},
      %{title: "Newest Lead", id: "newest_lead", column: :inserted_at, direction: :desc}
    ]
  end

  defp actions do
    [
      %{title: "Edit", action: "view-job", icon: "pencil"},
      %{title: "View client", action: "view-client", icon: "client-icon"},
      %{title: "Go to galleries", action: "view-galleries", icon: "photos-2"},
      %{title: "Send email", action: "open-compose", icon: "envelope"},
      %{title: "Complete", action: "complete-job", icon: "checkcircle"},
      %{title: "Archive", action: "confirm-archive-unarchive", icon: "trash"}
    ]
  end

  defp hide_action?(job, icon),
    do:
      (job.job_status.current_status == :archived || job.job_status.current_status == :completed) and
        (icon == "trash" || icon == "checkcircle")

  # credo:disable-for-next-line
  defp status_label(
         %{
           job_status: %{current_status: status},
           booking_proposals: booking_proposals,
           payment_schedules: payment_schedules
         } = job,
         time_zone
       ) do
    booking_proposal = booking_proposals |> List.first()
    unpaid? = payment_schedules |> Enum.any?(&is_nil(&1.paid_at))

    cond do
      status == :archived ->
        "Archived on #{format_date(job.archived_at, time_zone)}"

      status == :completed ->
        "Completed on #{format_date(job.completed_at, time_zone)}"

      status == :accepted ->
        "Awaiting on #{if(booking_proposal, do: booking_proposal.accepted_at, else: job.updated_at) |> format_date(time_zone)}"

      status == :answered ->
        "Pending on #{format_date(job.updated_at, time_zone)}"

      status == :sent ->
        "Created on #{format_date(job.updated_at, time_zone)}"

      !unpaid? ->
        "Created on #{format_date(job.updated_at, time_zone)}"

      !job.package ->
        "Pending on #{format_date(job.updated_at, time_zone)}"

      booking_proposal && !is_nil(booking_proposal.questionnaire_id) ->
        "Awaiting on #{signed_at(booking_proposal, job.updated_at) |> format_date(time_zone)}"

      booking_proposal && is_nil(booking_proposal.questionnaire_id) ->
        "Pending on #{signed_at(booking_proposal, job.updated_at) |> format_date(time_zone)}"

      true ->
        "Created on #{format_date(job.inserted_at, time_zone)}"
    end
  end

  defp signed_at(booking_proposal, date) do
    if(booking_proposal && booking_proposal.signed_at, do: booking_proposal.signed_at, else: date)
  end

  defp format_date(date, time_zone), do: strftime(time_zone, date, "%B %d, %Y")

  defp get_shoots(sort_direction, shoots, collapse?) do
    shoots
    |> Enum.sort_by(&DateTime.to_date(&1.starts_at), {sort_direction, Date})
    |> then(fn
      shoots when collapse? == false -> Enum.take(shoots, 3)
      shoots -> shoots
    end)
  end
end
