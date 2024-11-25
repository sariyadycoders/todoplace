defmodule TodoplaceWeb.Live.ClientLive.JobHistory do
  @moduledoc false

  use TodoplaceWeb, :live_view
  require Ecto.Query

  import TodoplaceWeb.JobLive.Shared, only: [status_badge: 1]
  import TodoplaceWeb.GalleryLive.Shared, only: [expired_at: 1]
  import TodoplaceWeb.Live.ClientLive.Shared

  alias Ecto.Query
  alias TodoplaceWeb.{JobLive.ImportWizard, JobLive}
  alias Todoplace.{Jobs, Job, Repo, Clients, Galleries}

  defmodule Pagination do
    @moduledoc false
    defstruct first_index: 1,
              last_index: 3,
              total_count: 0,
              limit: 12,
              after: nil,
              before: nil
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket
    |> get_client(id)
    |> assign_new(:pagination, fn -> %Pagination{} end)
    |> assign(:index, false)
    |> assign(:arrow_show, "contact details")
    |> assign(:job_types, Todoplace.JobType.all())
    |> assign(:client_tags, %{})
    |> assign_clients_job(id)
    |> assign_type_strings()
    |> ok()
  end

  @impl true
  def handle_params(params, _, socket) do
    socket
    |> is_mobile(params)
    |> noreply()
  end

  @impl true
  def handle_event("back_to_navbar", _, %{assigns: %{is_mobile: is_mobile}} = socket) do
    socket |> assign(:is_mobile, !is_mobile) |> noreply
  end

  @impl true
  def handle_event(
        "create-gallery",
        %{"job_id" => job_id},
        %{assigns: %{current_user: %{organization_id: organization_id} = current_user}} = socket
      ) do
    job_id = to_integer(job_id)

    gallery =
      case Galleries.get_galleries_by_job_id(job_id) do
        [] ->
          {:ok, gallery} =
            Galleries.create_gallery(current_user, %{
              job_id: job_id,
              name: job_id |> Jobs.get_job_by_id() |> Job.name(),
              type: :standard,
              client_link_hash: UUID.uuid4(),
              expired_at: expired_at(organization_id)
            })

          gallery

        [gallery | _] ->
          gallery
      end

    socket
    |> push_redirect(to: ~p"/galleries/#{gallery.id}?#{%{is_mobile: false}}")
    |> noreply()
  end

  @impl true
  def handle_event(
        "import-job",
        %{"id" => id},
        %{assigns: %{clients: clients, current_user: current_user}} = socket
      ) do
    client = clients |> Enum.find(&(&1.id == to_integer(id)))

    socket
    |> open_modal(ImportWizard, %{
      current_user: current_user,
      selected_client: client,
      step: :job_details
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "import-job",
        %{"id" => _id},
        %{assigns: %{client: client, current_user: current_user}} = socket
      ) do
    socket
    |> open_modal(ImportWizard, %{
      current_user: current_user,
      selected_client: client,
      step: :job_details
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "show_dropdown",
        %{"show_index" => show_index},
        %{assigns: %{index: index}} = socket
      ) do
    show_index = to_integer(show_index)

    socket
    |> assign(index: if(show_index == index, do: false, else: show_index))
    |> noreply()
  end

  @impl true
  def handle_event(
        "page",
        %{"cursor" => cursor, "direction" => direction},
        %{assigns: %{client_id: client_id}} = socket
      ) do
    update_fn =
      case direction do
        "back" -> &%{&1 | after: nil, before: cursor, first_index: &1.first_index - &1.limit}
        "forth" -> &%{&1 | after: cursor, before: nil, first_index: &1.first_index + &1.limit}
      end

    socket |> update(:pagination, update_fn) |> assign_clients_job(client_id) |> noreply()
  end

  @impl true
  def handle_event(
        "page",
        %{"per-page" => per_page},
        %{assigns: %{client_id: client_id}} = socket
      ) do
    limit = to_integer(per_page)

    socket
    |> assign(:pagination, %Pagination{limit: limit, last_index: limit})
    |> assign_clients_job(client_id)
    |> noreply()
  end

  @impl true
  def handle_event("page", %{}, socket), do: socket |> noreply()

  defdelegate handle_event(event, params, socket), to: JobLive.Shared

  defdelegate handle_info(message, socket), to: JobLive.Shared

  defp get_client(%{assigns: %{current_user: user}} = socket, id) do
    case Clients.get_client(user, id: id) do
      nil ->
        socket |> redirect(to: "/clients")

      client ->
        socket |> assign(:client, client) |> assign(:client_id, client.id)
    end
  end

  defp assign_type_strings(%{assigns: %{live_action: live_action}} = socket) do
    if live_action == :jobs do
      socket
      |> assign(:type, %{singular: "job", plural: "jobs"})
    else
      socket
      |> assign(:type, %{singular: "lead", plural: "leads"})
    end
  end

  defp assign_clients_job(
         %{
           assigns: %{
             pagination: pagination
           }
         } = socket,
         client_id
       ) do
    %{entries: jobs, metadata: metadata} =
      Jobs.get_client_jobs_query(client_id)
      |> Query.order_by(desc: :updated_at)
      |> Repo.paginate(
        pagination
        |> Map.take([:before, :after, :limit])
        |> Map.to_list()
        |> Enum.concat(cursor_fields: [updated_at: :desc])
      )

    socket
    |> assign(
      jobs: jobs,
      pagination: %{
        pagination
        | total_count: metadata.total_count,
          after: metadata.after,
          before: metadata.before,
          last_index: pagination.first_index + Enum.count(jobs) - 1
      }
    )
  end

  def table_item(assigns) do
    assigns = assigns |> Enum.into(%{is_lead: assigns.job.job_status.is_lead})

    ~H"""
    <div class="py-0 md:py-2">
      <div class="font-bold">
        <%= Calendar.strftime(@job.inserted_at, "%m/%d/%y") %>
      </div>
      <div class="font-bold w-full">
        <a href={fetch_redirection_link(@is_lead, @job)}>
          <span class={
            classes("w-full text-blue-planning-300 underline", %{
              "truncate" => String.length(Job.name(@job)) > 29
            })
          }>
            <%= Job.name(@job) %>
          </span>
        </a>
      </div>
      <%= if @job.package do %>
        <div class="text-base-250 font-normal"><%= @job.package.name %></div>
      <% end %>
      <div class="text-base-250 font-normal mb-2">
        <%= Jobs.get_job_shooting_minutes(@job) %> minutes
      </div>
      <.status_badge job={@job} />
    </div>
    """
  end

  defp fetch_redirection_link(is_lead, job),
    do: "/#{if is_lead, do: "leads", else: "jobs"}/#{job.id}?request_from=job_history"

  defp dropdown_item(%{icon: icon} = assigns) do
    assigns = Enum.into(assigns, %{class: nil, id: nil})

    icon_text_class =
      if icon in ["trash", "closed-eye"], do: "text-red-sales-300", else: "text-blue-planning-300"

    assigns = assign(assigns, icon_text_class: icon_text_class)

    ~H"""
    <a
      {@link}
      class={"text-gray-700 block px-4 py-2 text-sm hover:bg-blue-planning-100 cursor-pointer #{@class} #{@icon}"}
      role="menuitem"
      tabindex="-1"
    >
      <.icon name={@icon} class={"w-4 h-4 fill-current #{@icon_text_class} inline mr-1"} />
      <%= @title %>
    </a>
    """
  end
end
