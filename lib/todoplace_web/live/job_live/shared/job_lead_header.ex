defmodule TodoplaceWeb.JobLive.Shared.JobLeadHeaderComponent do
  @moduledoc false

  use TodoplaceWeb, :live_component
  use Phoenix.Component

  import TodoplaceWeb.LiveHelpers

  import TodoplaceWeb.JobLive.Shared,
    only: [
      status_badge: 1,
      error: 1,
      send_proposal_button: 1
    ]

  alias Todoplace.{
    Job
  }

  @impl true
  def render(assigns) do
    ~H"""
    <header class="bg-white">
      <div class="px-6 pt-6 center-container">
        <div class="flex items-center">
          <.live_link to={case @request_from do
                "job_history" -> ~p"/clients/#{@job.client_id}/job-history"
                "gallery_index" -> ~p"/galleries"
                _ -> ~p"/jobs"
              end} class="rounded-full bg-base-200 flex items-center justify-center p-2.5 mt-2 mr-4">
            <.icon name="back" class="w-3 h-3 stroke-2"/>
          </.live_link>
          <.crumbs>
            <:crumb to={~p"/jobs"}>
              <%= action_name(@live_action, :plural) %>
            </:crumb>
            <:crumb><%= Job.name @job %></:crumb>
          </.crumbs>
        </div>

        <div class="flex flex-col justify-between md:flex-row">
          <div>
            <.title_header job={@job} />
            <div class="flex gap-4 mt-2">
              <.status_badge class="w-fit" job={@job} />
              <%= if @job.booking_event_id do %>
                <.badge color={:gray} class="text-base-250/50">
                  From Booking Event
                </.badge>
              <% end %>
            </div>
          </div>
          <div class="flex h-full md:mt-0 mt-6 gap-4">
            <div id="manage" phx-hook="Select" class="md:w-auto w-full">
              <button {testid("actions")} class="btn-tertiary flex items-center gap-3 text-blue-planning-300 md:w-auto w-full">
                Actions
                <.icon name="down" class="w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 open-icon" />
                <.icon name="up" class="hidden w-4 h-4 ml-auto mr-1 stroke-current stroke-3 text-blue-planning-300 close-icon" />
              </button>
              <ul class="flex-col bg-white border rounded-lg shadow-lg popover-content z-20 hidden">
                <li phx-click="open-compose" phx-value-client_id={@job.client_id} phx-value-is_thanks={"true"} class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold cursor-pointer">
                  <.icon name="envelope" class="inline-block w-4 h-4 mx-2 fill-current text-blue-planning-300" />
                  <a>Send an email</a>
                </li>
                <li phx-click="open_name_change" class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold cursor-pointer">
                  <.icon name="pencil" class="inline-block w-4 h-4 mx-2 fill-current text-blue-planning-300" />
                  <a>Edit <%= if @job.job_status.is_lead, do: "lead", else: "job" %> name</a>
                </li>
                <%= unless @job.completed_at do %>
                  <%= if !@job.archived_at and !@job.completed_at do %>
                    <li phx-click="confirm-archive-unarchive" phx-value-id={@job.id} class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold cursor-pointer">
                      <.icon name="trash" class="inline-block w-4 h-4 mx-2 fill-current text-red-sales-300" />
                      <a>Archive <%= if @job.job_status.is_lead, do: "lead", else: "job" %></a>
                    </li>
                  <% else %>
                    <li phx-click="confirm-archive-unarchive" phx-value-id={@job.id} class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold cursor-pointer">
                      <.icon name="plus" class="inline-block w-4 h-4 mx-2 fill-current text-blue-planning-300" />
                      <a>Unarchive <%= if @job.job_status.is_lead, do: "lead", else: "job" %></a>
                    </li>
                  <% end %>
                <% end %>
                <%= unless @job.job_status.is_lead do %>
                  <%= if !@job.archived_at and !@job.completed_at do  %>
                    <li phx-click="confirm_job_complete" class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold cursor-pointer">
                      <.icon name="checkcircle" class="inline-block w-4 h-4 mx-2 fill-current text-blue-planning-300" />
                      <a>Complete job</a>
                    </li>
                  <% end %>
                <% end %>
              </ul>
            </div>
            <%= cond do %>
              <% !@job.job_status.is_lead ->%>
              <% @proposal && (@proposal.sent_to_client || @proposal.accepted_at) -> %>
                <button class="btn-primary mt-2 md:mt-0 lg:mt-0 lg:w-auto md:w-auto w-full" phx-click="open-proposal" phx-value-action="details">View proposal</button>
              <% @job.job_status.is_lead -> %>
                <.send_proposal_button is_schedule_valid={@is_schedule_valid} package={@package} shoots={@shoots} stripe_status={@stripe_status} class="md:flex w-full md:w-auto" />
              <% true -> %>
            <% end %>
          </div>
        </div>

        <%= if @job.job_status.is_lead do %>
          <%= unless [:charges_enabled, :loading] |> Enum.member?(@stripe_status) do %>
            <div class="flex flex-col items-center px-4 py-2 mt-8 text-center rounded-lg md:flex-row bg-red-sales-300/10 sm:text-left">
              <.icon name="warning-orange-dark" class="inline-block w-4 h-4 mr-2"/>
              It looks like you haven’t setup Stripe yet. You won’t be able to send out a proposal until that is setup.
              <div class="flex-shrink-0 my-1 mt-4 md:ml-auto sm:max-w-xs sm:mt-0">
                <.live_component
                  module={TodoplaceWeb.StripeOnboardingComponent}
                  id={:stripe_onboarding_banner}
                  error_class="text-center"
                  current_user={@current_user}
                  class="btn-primary py-1 px-3 text-sm intro-stripe mx-auto block"
                  return_url={url(~p"/jobs/#{@job.id}")}
                  stripe_status={@stripe_status}
                />
              </div>
            </div>
          <% end %>
        <% end %>

        <%= if @job.job_status.is_lead do %>
          <.error message="You changed a shoot date. You need to review or fix your payment schedule date." button={%{title: "Edit payment schedule", action: "edit-package", class: "py-1 md:my-1 my-2"}} icon_class="w-6 h-6" class={classes(%{"md:hidden hidden" => @is_schedule_valid})}/>
        <% end %>

        <hr class="my-4 border-gray-200" />

        <.tabs_nav tab_active={@tab_active} tabs={@tabs} socket={@socket} />
      </div>
    </header>
    """
  end

  def title_header(assigns) do
    ~H"""
    <h1 class="flex items-center text-4xl font-bold md:justify-start">
      <div class="flex items-center max-w-4xl">
        <%= Job.name @job %>
      </div>
      <div class="px-5">
        <button type="button" phx-click="open_name_change" class="bg-base-200 p-2 rounded-lg btn-tertiary">
          <.icon name="pencil" class="w-4 h-4 fill-current text-blue-planning-300" />
        </button>
      </div>
    </h1>
    """
  end

  def tabs_nav(assigns) do
    ~H"""
    <ul class="flex overflow-auto gap-6 mb-6 py-6 md:py-0">
      <%= for {true, %{name: name, action: action, concise_name: concise_name, redirect_route: redirect_route}} <- @tabs do %>
        <li class={classes("text-blue-planning-300 font-bold text-lg border-b-4 transition-all shrink-0", %{"opacity-100 border-b-blue-planning-300" => @tab_active === concise_name, "opacity-40 border-b-transparent hover:opacity-100" => @tab_active !== concise_name})}>
          <button type="button" phx-click={action} phx-value-tab={concise_name} phx-value-to={redirect_route}><%= name %></button>
        </li>
      <% end %>
    </ul>
    """
  end
end
