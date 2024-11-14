defmodule TodoplaceWeb.GalleryLive.Settings.ManageGalleryAnalyticsComponent do
  @moduledoc false
  use TodoplaceWeb, :live_component
  alias TodoplaceWeb.GalleryLive.Shared, as: GalleryLiveShared
  alias Todoplace.Repo

  @impl true
  def update(
        %{
          gallery:
            %{gallery_analytics: gallery_analytics, download_tracking: download_tracking} =
              gallery,
          user: user
        },
        socket
      ) do
    %{email: email} = Repo.preload(gallery, job: :client) |> Map.get(:job) |> Map.get(:client)

    socket
    |> assign(
      gallery_analytics: assign_unique_emails_list(gallery_analytics),
      download_tracking: download_tracking,
      gallery_client_email: email,
      time_zone: user.time_zone
    )
    |> ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3>Gallery analytics</h3>
        <div class="flex justify-between">
          <p class="font-sans text-base-250">You can see if your client has logged into the gallery or send a reminder!</p>
        </div>
        <div class="flex flex-col mt-2">
          <p class="font-bold">Emails that have viewed:</p>
          <%= if @gallery_analytics != [] do %>
            <div class="grid md:grid-cols-2">
              <%= for gallery_analytic <- @gallery_analytics do %>
              <div class="flex flex-row mt-2 items-center">
                <div class="flex">
                  <div class="flex items-center justify-center flex-shrink-0 w-8 h-8 rounded-full bg-blue-planning-300">
                    <.icon name="envelope" class="w-4 h-4 text-white fill-current"/>
                  </div>
                </div>
                <div class="flex flex-col ml-2">
                  <p class="text-base-250 font-bold">
                    <%= if gallery_analytic["email"] == @gallery_client_email do %>
                      <%= gallery_analytic["email"] <> " (client)" %>
                    <% else %>
                      <%= gallery_analytic["email"] %>
                    <% end %>
                  </p>
                  <p class="text-base-250 font-normal">Viewed: <%= format_date_string(gallery_analytic["viewed_at"], @time_zone) %></p>
                </div>
              </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-base-250">No one has viewed yet!</p>
          <% end %>
        </div>
        <div class="flex flex-col mt-2">
          <p class="font-bold">Download tracking:</p>
          <%= unless @download_tracking == [] || is_nil(@download_tracking) do %>
            <div class="grid md:grid-cols-2">
              <%= for download_tracking <- @download_tracking do %>
                <div class="flex flex-row mt-2 items-center">
                  <div class="flex">
                    <div class="flex items-center justify-center flex-shrink-0 w-8 h-8 rounded-full bg-blue-planning-300">
                      <.icon name="photos-2" class="w-4 h-4 text-white fill-current"/>
                    </div>
                  </div>
                  <div class="flex flex-col ml-2">
                    <p class="text-base-250 font-bold">
                      <%= if download_tracking["email"] == @gallery_client_email do %>
                        <%= download_tracking["email"] <> " (client)" %>
                      <% else %>
                        <%= download_tracking["email"] %>
                      <% end %>
                    </p>
                    <p class="text-base-250 font-normal">Downloaded <%= download_tracking["name"] %> on <%= format_date_string(download_tracking["downloaded_at"], @time_zone) %></p>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-base-250">No one has downloaded yet!</p>
          <% end %>
        </div>
        <div {testid("send-reminder")} class="flex flex-row-reverse items-center justify-between w-full mt-5 lg:items-start">
            <a class={classes("btn-settings px-5 hover:cursor-pointer", %{"hidden" => @gallery_analytics != []})} phx-click="client-link">Send reminder</a>
        </div>
    </div>
    """
  end

  @impl true
  defdelegate handle_event(name, params, socket), to: GalleryLiveShared

  defp assign_unique_emails_list(gallery_analytics) do
    (gallery_analytics || [])
    |> Enum.sort_by(& &1["viewed_at"], &>=/2)
    |> Enum.uniq_by(& &1["email"])
  end

  defp format_date_string(date_string, time_zone) do
    # convert utc to user time_zone
    {:ok, datetime, _} = DateTime.from_iso8601(date_string)
    converted_datetime = DateTime.shift_zone!(datetime, time_zone)
    date_time_zone = DateTime.to_iso8601(converted_datetime)

    [year, month, day] =
      date_time_zone
      |> String.slice(0..9)
      |> String.split("-")

    "#{month}/#{day}/#{String.slice(year, 2..3)}"
  end
end
