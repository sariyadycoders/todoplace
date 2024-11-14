defmodule TodoplaceWeb.ViewHelpers do
  use TodoplaceWeb, :html

  alias TodoplacePayments

  import TodoplaceWeb.LiveHelpers,
    only: [
      testid: 1,
      classes: 2,
      icon: 1,
      classes: 1,
      base_url: 1,
      format_date_via_type: 1
    ]

  import TodoplaceWeb.Live.Profile.Shared, only: [photographer_logo: 1]
  import TodoplaceWeb.Shared.StickyUpload, only: [sticky_upload: 1, gallery_top_banner: 1]
  import TodoplaceWeb.Shared.Sidebar, only: [main_header: 1, get_classes_for_main: 1]

  use Phoenix.Component

  def make_status(schedule) do
    cond do
      not is_nil(schedule.paid_at) ->
        "Paid #{schedule.paid_at |> format_date_via_type()}"

      DateTime.compare(schedule.due_at, DateTime.utc_now()) == :lt ->
        "Overdue #{schedule.due_at |> format_date_via_type()}"

      DateTime.compare(schedule.due_at, DateTime.utc_now()) == :gt ->
        "Upcoming #{schedule.due_at |> format_date_via_type()}"
    end
  end

  def status_class(status_string) do
    status = String.split(status_string, " ") |> Enum.at(0)

    case status do
      "Paid" ->
        "text-green-finances-300"

      "Overdue" ->
        "text-red-sales-300"

      "Upcoming" ->
        "text-black"
    end
  end

  defp default_meta_tags do
    for(
      {meta_name, config_key} <- %{
        "google-site-verification" => :google_site_verification,
        "google-maps-api-key" => :google_maps_api_key
      },
      reduce: %{}
    ) do
      acc ->
        case Application.get_env(:todoplace, config_key) do
          nil -> acc
          value -> Map.put(acc, meta_name, value)
        end
    end
  end

  def meta_tags(nil) do
    meta_tags(%{})
  end

  def meta_tags(attrs_list) do
    Map.merge(default_meta_tags(), attrs_list)
  end

  def dynamic_background_class(%{main_class: main_class}), do: main_class

  def dynamic_background_class(_), do: nil

  defp flash_styles,
    do: [
      {:error, "error", "text-red-sales-300"},
      {:info, "info", "text-blue-planning-300"},
      {:success, "tick", "text-green-finances-300"}
    ]

  def flash(flash) do
    assigns = %{flash: flash}

    ~H"""
    <div>
      <%= for {key, icon, text_color} <- flash_styles(), message <- [live_flash(@flash, key)], message do %>
        <%= if(key in [:error, :info, :success])  do %>
          <div
            phx-hook="Flash"
            id={"flash-#{DateTime.to_unix(DateTime.utc_now)}"}
            phx-click="lv:clear-flash"
            phx-value-key={key}
            title={key}
            class="fixed right-10-md right-0 top-1.5 z-40 max-w-lg px-1.5 px-0-md flash"
            role="alert"
          >
            <div class="flex bg-white rounded-lg shadow-lg cursor-pointer">
              <div class={classes(["flex items-center justify-center p-3", text_color])}>
                <.icon name={icon} class="w-6 h-6 stroke-current" />
              </div>
              <div class="flex items-center justify-center font-sans flex-grow px-3 py-2 mr-7">
                <p><%= message %></p>
              </div>
              <div class="flex items-center justify-center mr-3">
                <.icon name="close-x" class="w-3 h-3 stroke-current" />
              </div>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  def google_analytics(assigns) do
    ~H"""
    <!-- Global site tag (gtag.js) - Google Analytics -->
    <script async src={"https://www.googletagmanager.com/gtag/js?id=#{@gaId}"}>
    </script>
    <script>
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());

      gtag('config', '<%= @gaId %>');
    </script>
    """
  end

  def google_tag_manager(assigns) do
    ~H"""
    <!-- Google Tag Manager -->
    <script>
      (function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':
      new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],
      j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src=
      'https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);
      })(window,document,'script','dataLayer','<%= @gtmId %>');
    </script>
    <!-- End Google Tag Manager -->

    <!-- Google Tag Manager (noscript) -->
    <noscript>
      <iframe
        src={"https://www.googletagmanager.com/ns.html?id=#{@gtmId}"}
        height="0"
        width="0"
        style="display:none;visibility:hidden"
      >
      </iframe>
    </noscript>
    <!-- End Google Tag Manager (noscript) -->
    """
  end

  def help_chat_widget(assigns) do
    assigns = assigns |> Enum.into(%{current_user: nil}) |> get_intercom_id()

    ~H"""
    <%= if @intercom_id do %>
      <%= if @current_user do %>
        <div
          id="load-intercom-user"
          phx-hook="IntercomLoad"
          data-intercom-id={@intercom_id}
          data-has-user="true"
          data-name={@current_user.name}
          data-email={@current_user.email}
          data-user-id={@current_user.id}
          data-created-at={@current_user.inserted_at}
          data-has-logo={"#{!is_nil(TodoplaceProfiles.logo_url(@current_user.organization))}"}
          data-is-public-profile-active={"#{TodoplaceProfiles.enabled?(@current_user.organization)}"}
          data-is-stripe-setup={"#{if Payments.simple_status(@current_user.organization) == :charges_enabled, do: true, else: false}"}
          data-currency-type={"#{TodoplaceUserCurrencies.get_user_currency(@current_user.organization.id).currency}"}
          data-accepted-payment-methods={"#{Payments.map_payment_opts_to_stripe_opts(@current_user.organization) |> Payments.check_and_map_offline(@current_user.organization) |> Jason.encode!()}"}
          data-has-two-way-calendar-sync={"#{TodoplaceNylasDetails.user_has_token?(@current_user)}"}
          data-number-of-galleries={"#{TodoplaceGalleries.get_gallery_count_for_organization(@current_user.organization.id)}"}
          data-number-of-contracts={"#{TodoplaceContracts.count_for_organization(@current_user.organization.id)}"}
        >
        </div>
      <% else %>
        <div
          id="load-intercom"
          phx-hook="IntercomLoad"
          data-intercom-id={@intercom_id}
          data-has-user="false"
        >
        </div>
      <% end %>
      <.reattach_activator intercom_id={@intercom_id} />
    <% end %>
    """
  end

  def subscription_ending_soon(%{current_user: current_user} = assigns) do
    subscription = current_user |> TodoplaceSubscriptions.subscription_ending_soon_info()
    assigns = Enum.into(assigns, %{subscription: subscription})

    case assigns.type do
      "header" ->
        ~H"""
        <div class={classes(%{"hidden" => @subscription.hidden_for_days?})}>
          <.link navigate={Routes.user_settings_path(@socket, :edit)} class="flex gap-2 items-center mr-4">
            <h6 class="text-xs italic text-gray-250 opacity-50">
              Trial ending soon! <%= ngettext(
                "1 day",
                "%{count} days",
                Map.get(@subscription, :days_left, 0)
              ) %> left.
            </h6>
            <button class="hidden sm:block text-xs rounded-lg px-4 py-1 border border-blue-planning-300 font-semibold hover:bg-blue-planning-100">
              Renew plan
            </button>
          </.link>
        </div>
        """

      "banner" ->
        ~H"""
        <div
          {testid("subscription-top-banner")}
          class={classes(@class, %{"hidden" => @subscription.hidden?})}
        >
          <.icon name="clock-filled" class="lg:w-5 lg:h-5 w-8 h-8 mr-2" />
          <span>
            You have <%= ngettext("1 day", "%{count} days", Map.get(@subscription, :days_left, 0)) %> left before your subscription ends.
            <.link navigate={Routes.user_settings_path(@socket, :edit)}>
              <span class="font-bold underline px-1 cursor-pointer">Click here</span>
            </.link>
            to upgrade.
          </span>
        </div>
        """

      _ ->
        ~H"""
        <div {testid("subscription-footer")} class={classes(@class, %{"hidden" => @subscription.hidden?})}>
          <.link navigate={Routes.user_settings_path(@socket, :edit)}>
            <%= ngettext("1 day", "%{count} days", Map.get(@subscription, :days_left, 0)) %> left until your subscription ends
          </.link>
        </div>
        """
    end
  end

  def admin_banner(assigns) do
    ~H"""
    <div
      class="hidden fixed top-4 right-4 p-2 bg-red-sales-300/25 rounded-lg text-red-sales-300 shadow-lg backdrop-blur-md z-[1000]"
      id="admin-banner"
    >
      <span class="font-bold">You are logged in as a user, please log out when finished</span>
      <%= link("Logout",
        to: Routes.user_session_path(@socket, :delete),
        method: :delete,
        class: "ml-4 btn-tertiary px-2 py-1 text-sm text-red-sales-300"
      ) %>
    </div>
    """
  end

  def stripe_setup_banner(%{current_user: current_user} = assigns) do
    stripe_status = Payments.simple_status(current_user)
    assigns = Enum.into(assigns, %{stripe_status: stripe_status})

    ~H"""
    <%= if !Enum.member?([:charges_enabled, :loading], @stripe_status) do %>
      <div class="bg-gray-100 py-3 border-b border-b-white">
        <div class="center-container px-6">
          <div class="flex justify-between items-center gap-2">
            <details class="cursor-pointer text-base-250 group">
              <summary class="flex items-center font-bold text-black">
                <.icon name="confetti" class="w-5 h-5 mr-2 text-blue-planning-300" />
                Get paid within Todoplace!
                <.icon
                  name="down"
                  class="w-4 h-4 stroke-current stroke-2 text-blue-planning-300 ml-2 group-open:rotate-180"
                />
              </summary>
              To accept money from bookings & galleries, connect your Stripe account and add a payment method.
              <em>
                We also offer offline payments for bookings only.
                <a
                  href={"#{base_url(:support)}article/32-set-up-stripe"}
                  class="underline"
                  target="_blank"
                  rel="noreferrer"
                >
                  Learn more
                </a>
              </em>
            </details>
            <div class="flex gap-2">
              <a
                href={Routes.finance_settings_path(@socket, :index)}
                class="flex text-xs items-center px-2 py-1 btn-tertiary bg-blue-planning-300 text-white hover:bg-blue-planning-300/75 flex-shrink-0"
              >
                <.icon name="settings" class="inline-block w-4 h-4 fill-current text-white mr-1" />
                Connect Stripe
              </a>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  def main_footer(assigns) do
    assigns = assign_new(assigns, :footer_class, fn -> nil end)

    ~H"""
    <div class="mt-12"></div>
    <footer class={"mt-auto #{@footer_class} sm:block bg-base-300 text-white"}>
      <div class="px-6 center-container py-10">
        <div class="flex justify-between gap-8">
          <nav class="flex flex-col sm:flex-row text-lg font-bold mt-4 w-full items-center gap-2">
            <ul class="flex">
              <li>
                <a href={"#{base_url(:support)}"} target="_blank" rel="noopener noreferrer">
                  Help center
                </a>
              </li>
              <%= if @current_user && Application.get_env(:todoplace, :intercom_id) do %>
                <li><a href="#help" class="ml-10 open-help">Contact us</a></li>
              <% end %>
              <li>
                <a
                  class="ml-10"
                  href={"#{base_url(:marketing)}blog"}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Blog
                </a>
              </li>
              <li>
                <a class="ml-10" href="/users/settings#rewardful-affiliate">
                  Get paid to share Todoplace!
                </a>
              </li>
            </ul>

            <.icon name="logo-shoot-higher" class="w-24 h-10 sm:h-20 sm:w-32 sm:ml-auto mt-4 md:mt-0" />

            <.subscription_ending_soon
              type="footer"
              socket={@socket}
              current_user={@current_user}
              class="flex ml-auto bg-white text-black rounded px-4 py-2 items-center text-sm"
            />
          </nav>
        </div>
        <hr class="my-8 opacity-30" />
        <div class="flex flex-col lg:flex-row">
          <ul class="flex lg:ml-auto items-center">
            <li class="text-base-250 text-xs">
              <a
                href={"#{base_url(:marketing)}terms-conditions"}
                target="_blank"
                rel="noopener noreferrer"
              >
                Terms
              </a>
            </li>
            <li class="text-base-250 mx-3.5">|</li>
            <li class="text-base-250 text-xs">
              <a
                href={"#{base_url(:marketing)}privacy-policy"}
                target="_blank"
                rel="noopener noreferrer"
              >
                Privacy Policy
              </a>
            </li>
            <li class="text-base-250 mx-3.5">|</li>
            <li class="text-base-250 text-xs">
              <a
                href={"#{base_url(:marketing)}privacy-policy#ccpa"}
                target="_blank"
                rel="noopener noreferrer"
              >
                California Privacy
              </a>
            </li>
          </ul>
        </div>
      </div>
      <button
        id="scroll-top"
        phx-hook="ScrollToTop"
        class="bg-blue-planning-300 p-2 text-white fixed bottom-5 right-24 sm:right-20 rounded-lg shadow-2xl shadow-black"
      >
        <.icon name="up" class="w-4 h-4 stroke-2 text-white" />
      </button>
    </footer>
    """
  end

  defp footer_nav(assigns) do
    organization = load_organization(assigns.gallery)
    assigns = Enum.into(assigns, %{organization: organization})

    ~H"""
    <nav class="flex text-lg">
      <.photographer_logo organization={@organization} />
      <div class="flex gap-6 items-center ml-auto pt-3">
        <div class="flex flex-col">
          <%= link("Logout",
            to:
              Routes.user_session_path(@socket, :delete, client_link_hash: @gallery.client_link_hash),
            method: :delete,
            class: "text-sm text-base-250 inline-block"
          ) %>
          <div class="border-b border-base-250 -mt-1"></div>
        </div>
        <a
          class="flex items-center justify-center px-2.5 py-1 text-base-300 bg-base-100 border border-base-300 hover:text-base-100 hover:bg-base-300"
          phx-hook="OpenCompose"
          id="open-compose"
        >
          <.icon name="envelope" class="mr-2 w-4 h-4 fill-current" /> Contact
        </a>
      </div>
    </nav>
    <hr class="my-8 opacity-100 border-base-200" />
    <div class="flex text-base-250 flex-col sm:flex-row">
      <div class="flex justify-center">
        ©<%= DateTime.utc_now().year %> <span class="font-base-300 font-bold ml-2"><%= @organization.name %></span>. All Rights Reserved
      </div>
      <div class="flex md:ml-auto justify-center">
        Powered by
        <a
          href={"#{base_url(:marketing)}terms-conditions"}
          class="underline ml-1"
          target="_blank"
          rel="noopener noreferrer"
        >
          <b>Todoplace</b>
        </a>
      </div>
    </div>
    """
  end

  defp reattach_activator(assigns) do
    ~H"""
    <script>
      (function(){var w=window;var ic=w.Intercom;if(typeof ic==="function"){ic('reattach_activator');ic('update',w.intercomSettings);}else{var d=document;var i=function(){i.c(arguments);};i.q=[];i.c=function(args){i.q.push(args);};w.Intercom=i;var l=function(){var s=d.createElement('script');s.type='text/javascript';s.async=true;s.src='https://widget.intercom.io/widget/<%= @intercom_id %>';var x=d.getElementsByTagName('script')[0];x.parentNode.insertBefore(s,x);};if(document.readyState==='complete'){l();}else if(w.attachEvent){w.attachEvent('onload',l);}else{w.addEventListener('load',l,false);}}})();
    </script>
    """
  end

  defp load_organization(gallery) do
    gallery
    |> TodoplaceRepo.preload([job: [client: :organization]], force: true)
    |> extract_organization()
  end

  defp get_intercom_id(assigns),
    do: assign(assigns, :intercom_id, Application.get_env(:todoplace, :intercom_id))

  defp extract_organization(%{job: %{client: %{organization: organization}}}), do: organization
end
