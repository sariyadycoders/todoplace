defmodule TodoplaceWeb.Live.User.Welcome.AccordionComponent do
  @moduledoc "restart tour"
  alias Todoplace.Onboarding.Welcome
  use TodoplaceWeb, :live_component

  alias Todoplace.{
    Onboardings.Welcome
  }

  @impl true
  def update(%{tracked_state: tracked_state, slug: _slug} = assigns, socket) do
    socket
    |> assign(assigns)
    |> assign(:is_open, false)
    |> assign(:is_complete, determine_is_complete(tracked_state))
    |> then(fn socket ->
      maybe_fire_complete_event(socket, assigns)
    end)
    |> ok()
  end

  def update(%{id: _, group: group, slug: slug}, socket) do
    handle_event_complete(socket, true, group, slug) |> ok()
  end

  @impl true
  def render(assigns) do
    assigns =
      Enum.into(assigns, %{
        complete_text: nil,
        complete_action: nil,
        secondary_text: nil,
        secondary_action: nil
      })

    ~H"""
    <div class="bg-white rounded-lg">
      <div class="flex gap-4 cursor-pointer p-6 border rounded-t-lg" phx-click="toggle-open" phx-target={@myself}>
        <.icon name={@icon} class="w-6 h-6 flex-shrink-0 text-blue-planning-300" />
        <h2 class="font-bold text-xl"><%= @heading %></h2>
        <div class="ml-auto flex items-center gap-4">
          <%= if @is_complete do %>
            <div class="flex items-center gap-2">
              <.icon name="checkcircle" class="w-6 h-6 text-green-finances-200 flex-shrink-0" />
              <p class="text-base-250">Complete</p>
            </div>
          <% else %>
            <p class="text-base-250 flex-shrink-0"><%= @time %></p>
          <% end %>
          <%= if @is_open do %>
            <.icon name="up" class="w-6 h-6 text-blue-planning-300 flex-shrink-0" />
          <% else %>
            <.icon name="down" class="w-6 h-6 text-blue-planning-300 flex-shrink-0" />
          <% end %>
        </div>
      </div>
      <div class={classes("border-b-8 rounded-b-lg transition-all border", %{"rounded-b-none" => @is_open, "border-green-finances-200" => @is_complete, "border-base-200" => !@is_complete})}></div>
      <div class={classes("p-6 border rounded-b-lg", %{"hidden" => !@is_open})}>
        <%= if @is_complete do %>
          <div class="bg-green-finances-200/20 p-2 flex items-center gap-2 text-green-finances-200 rounded-lg mb-6">
            <.icon name="checkcircle" class="w-6 h-6 flex-shrink-0" />
            <p class="font-bold">Step is complete</p>
          </div>
        <% end %>
        <div class="grid md:grid-cols-2 grid-cols-1 gap-10">
          <div>
            <%= if @left_panel do %>
              <div class="text-base-250 space-y-4">
                <%= render_slot(@left_panel) %>
              </div>
            <% end %>
            <%= if @slug == "connect-stripe" do %>
              <.live_component module={TodoplaceWeb.StripeOnboardingComponent} id={:stripe_onboarding}
                error_class="text-right"
                class="btn-primary inline-block mt-6"
                container_class="w-auto"
                current_user={@current_user}
                return_url={~p"/users/welcome"}
                stripe_status={@stripe_status}
              />
            <% end %>
            <%= if @complete_text && @complete_action do %>
              <button type="button" phx-click={@complete_action} phx-value-id={@id} phx-value-complete_action={@complete_action} phx-value-group={@group} phx-value-slug={@slug} class="btn-primary block mt-6">
                <%= @complete_text %>
              </button>
            <% end %>
            <%= if @secondary_text && @secondary_action do %>
              <button type="button" phx-click={@secondary_action} class="link mt-2 flex items-center gap-2">
                <%= @secondary_text %> <.icon name="external-link" class="w-4 h-4 text-blue-planning-300 flex-shrink-0" />
              </button>
            <% end %>
          </div>
          <div>
            <%= if @right_panel do %>
              <%= render_slot(@right_panel) %>
            <% end %>
          </div>
        </div>
        <div class="flex justify-end text-base-250 mt-4">
          <button class="btn-tertiary flex items-center gap-2" phx-click="toggle-complete" phx-target={@myself} phx-value-slug={@slug} phx-value-group={@group} type="button">
            <%= if @is_complete do %>
              <.icon name="checkclose" class="w-6 h-6 flex-shrink-0 text-red-sales-300" />
               Mark incomplete
            <% else %>
              <.icon name="checkcircle" class="w-6 h-6 flex-shrink-0 text-green-finances-200" />
              Mark complete
            <% end %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  def youtube_video(assigns) do
    assigns =
      Enum.into(assigns, %{
        video_id: "AIflWbsD-_Q"
      })

    ~H"""
    <iframe class="aspect-video w-full" src={"https://www.youtube.com/embed/#{@video_id}"} title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
    """
  end

  @impl true
  def handle_event(
        "toggle-open",
        _,
        %{assigns: %{is_open: is_open}} = socket
      ) do
    socket
    |> assign(:is_open, !is_open)
    |> noreply()
  end

  @impl true
  def handle_event(
        "toggle-complete",
        %{"group" => group, "slug" => slug},
        %{
          assigns: %{
            is_complete: is_complete
          }
        } = socket
      ) do
    handle_event_complete(socket, !is_complete, group, slug) |> noreply()
  end

  defp handle_event_complete(
         %{
           assigns: %{
             current_user: current_user
           }
         } = socket,
         is_complete,
         group,
         slug
       ) do
    case Welcome.insert_or_update_welcome_by_slug(current_user, slug, group, is_complete) do
      {:ok, _} ->
        send(
          self(),
          {:is_complete_update,
           %{
             is_complete: is_complete,
             is_success: true
           }}
        )

        socket
        |> assign(:is_complete, is_complete)

      {:error, _} ->
        send(
          self(),
          {:is_complete_update,
           %{
             is_complete: is_complete,
             is_success: false
           }}
        )

        socket
        |> assign(:is_complete, is_complete)
    end
  end

  defp determine_is_complete(tracked_state) do
    if is_nil(tracked_state), do: false, else: !is_nil(tracked_state.completed_at)
  end

  defp maybe_fire_complete_event(
         socket,
         %{tracked_state: tracked_state, group: group, slug: slug} = assigns
       ) do
    completed_already = Map.get(assigns, :completed_already)
    is_complete = determine_is_complete(tracked_state)

    if completed_already == true && is_complete == false do
      handle_event_complete(socket, true, group, slug)
    else
      socket
    end
  end
end
