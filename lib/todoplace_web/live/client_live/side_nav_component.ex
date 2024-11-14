defmodule TodoplaceWeb.Live.ClientLive.SideNavComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component

  @impl true
  def update(
        %{
          id: id,
          client: client,
          arrow_show: arrow_show,
          is_mobile: is_mobile
        },
        socket
      ) do
    socket
    |> assign(:id, id)
    |> assign(:is_mobile, is_mobile)
    |> assign(:client, client)
    |> assign(:arrow_show, arrow_show)
    |> ok()
  end

  defp bar(assigns) do
    ~H"""
    <div class={@class}>
      <.link navigate={@route}>
        <div class="flex items-center py-3 pl-3 pr-4 overflow-hidden text-sm rounded lg:h-11 lg:pl-2 lg:py-4 transition duration-300 ease-in-out text-ellipsis whitespace-nowrap hover:text-blue-planning-300">
          <div class="flex items-center justify-center flex-shrink-0 w-8 h-8 rounded-full bg-blue-planning-300">
              <.icon name={@icon} class="w-4 h-4 text-white"></.icon>
          </div>
          <div class="ml-3">
            <span class={classes(%{"text-blue-planning-300" => @arrow_show})}><%= @title %></span>
          </div>
        </div>
      </.link>
    </div>
    """
  end
end
