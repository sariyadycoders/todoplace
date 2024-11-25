defmodule TodoplaceWeb.LiveHelpers do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TodoplaceWeb.Endpoint,
    router: TodoplaceWeb.Router,
    statics: TodoplaceWeb.static_paths()

  alias Todoplace.{Onboardings, PaymentSchedules, BookingProposal}

  import Phoenix.LiveView
  import Phoenix.Component
  import TodoplaceWeb.Gettext, only: [dyn_gettext: 1]
  import Todoplace.Profiles, only: [logo_url: 1]
  require Logger

  def open_modal(socket, component, assigns \\ %{})

  # main process, modal pid is assigned
  def open_modal(
        %{assigns: %{modal_pid: modal_pid} = parent_assigns} = socket,
        component,
        %{assigns: assigns} = config
      )
      when is_pid(modal_pid) do
    send(
      modal_pid,
      {:modal, :open, component,
       config
       |> Map.put(
         :assigns,
         assigns
         |> Map.merge(Map.take(parent_assigns, [:live_action]))
       )}
    )

    socket
  end

  # called with raw assigns map
  def open_modal(
        %{assigns: %{modal_pid: modal_pid}} = socket,
        component,
        assigns
      )
      when is_pid(modal_pid),
      do: socket |> open_modal(component, %{assigns: assigns})

  # modal process
  def open_modal(
        %{view: TodoplaceWeb.LiveModal} = socket,
        component,
        config
      ),
      do: socket |> assign(modal_pid: self()) |> open_modal(component, config)

  # main process, before modal pid is assigned
  def open_modal(
        socket,
        component,
        config
      ) do
    socket
    |> assign(queued_modal: {component, config})
  end

  # close from main process
  def close_modal(%{assigns: %{modal_pid: modal_pid}} = socket) do
    send(modal_pid, {:modal, :close})

    socket
  end

  # close from within modal process
  def close_modal(socket) do
    send(self(), {:modal, :close})

    socket
  end

  def strftime("" <> time_zone, time, format) do
    time
    |> DateTime.shift_zone!(time_zone)
    |> Calendar.strftime(format)
  end

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def icon(%{name: name} = assigns) do
    assigns =
      assigns
      |> Enum.into(%{
        width: nil,
        height: nil,
        class: nil,
        style: nil,
        path: Todoplace.Icon.public_path(name, TodoplaceWeb.Endpoint, &static_path/2)
      })

    ~H"""
    <svg width={@width} height={@height} class={@class} style={@style}>
      <use href={@path} />
    </svg>
    """
  end

  def icon_button(%{href: href} = assigns) do
    assigns =
      assigns
      |> Map.put(
        :rest,
        Map.drop(assigns, [:color, :icon, :inner_block, :class, :disabled, :target])
      )
      |> Enum.into(%{
        class: "",
        target: nil,
        disabled: false,
        inner_block: nil,
        icon_class: "",
        text_color: "text-#{assigns.color}"
      })

    ~H"""
    <a
      href={if @disabled, do: "javascript:void(0)", else: href}
      target={unless @disabled, do: @target}
      class={
        classes(
          "btn-tertiary flex items-center px-2 py-1 font-sans rounded-lg hover:opacity-75 transition-colors #{@text_color} #{@class}",
          %{"opacity-75 hover:cursor-not-allowed" => @disabled}
        )
      }
      {@rest}
    >
      <.icon
        name={@icon}
        class={classes("w-4 h-4 fill-current text-#{@color}", %{"mr-2" => @inner_block})}
      />
      <%= if @inner_block do %>
        <%= render_slot(@inner_block) %>
      <% end %>
    </a>
    """
  end

  def icon_button(assigns) do
    assigns =
      assigns
      |> Enum.into(%{
        class: "",
        disabled: false,
        inner_block: nil,
        icon_class: "",
        text_color: "text-#{assigns.color}"
      })
      |> Map.put(
        :rest,
        Map.drop(assigns, [
          :color,
          :icon,
          :inner_block,
          :class,
          :disabled,
          :text_color,
          :__changed__
        ])
      )

    ~H"""
    <button
      type="button"
      class={
        classes("btn-tertiary flex items-center whitespace-nowrap #{@text_color} #{@class}", %{
          "opacity-50 hover:opacity-30 hover:cursor-not-allowed" => @disabled
        })
      }
      disabled={@disabled}
      {@rest}
    >
      <.icon
        name={@icon}
        class={
          classes("w-4 h-4 fill-current text-#{@color} #{@icon_class}", %{"mr-2" => @inner_block})
        }
      />
      <%= if @inner_block do %>
        <%= render_slot(@inner_block) %>
      <% end %>
    </button>
    """
  end

  def icon_button_simple(assigns) do
    assigns =
      assigns
      |> Map.put(
        :rest,
        Map.drop(assigns, [:color, :icon, :inner_block, :class, :disabled, :icon_class])
      )
      |> Enum.into(%{class: "", disabled: false, inner_block: nil})

    ~H"""
    <button
      type="button"
      class={
        classes("flex items-center px-2 py-1 font-sans hover:opacity-75 #{@class}", %{
          "opacity-50 hover:opacity-30 hover:cursor-not-allowed" => @disabled
        })
      }
      }
      disabled={@disabled}
      {@rest}
    >
      <.icon name={@icon} class={"fill-current text-#{@color} #{@icon_class}"} />
      <%= if @inner_block do %>
        <%= render_slot(@inner_block) %>
      <% end %>
    </button>
    """
  end

  def button_simple(assigns) do
    assigns =
      assigns
      |> Enum.into(%{
        class: "",
        color: "blue-planning-300",
        icon_class: "",
        inner_block: nil,
        disabled: false
      })

    ~H"""
    <button
      type="button"
      class={
        classes("flex items-center px-2 py-1 font-sans hover:opacity-75 #{@class}", %{
          "opacity-50 hover:opacity-30 hover:cursor-not-allowed" => @disabled
        })
      }
      }
      disabled={@disabled}
    >
      <.icon name={@icon} class={"fill-current text-#{@color} #{@icon_class}"} />
      <%= if @inner_block do %>
        <%= render_slot(@inner_block) %>
      <% end %>
    </button>
    """
  end

  def button_element(%{element: "a"} = assigns) do
    attrs = Map.drop(assigns, [:inner_block, :__changed__, :element])
    assigns = Enum.into(assigns, %{attrs: attrs})

    ~H"""
    <a {@attrs}><%= render_slot(@inner_block) %></a>
    """
  end

  def button_element(%{element: "button"} = assigns) do
    attrs = Map.drop(assigns, [:inner_block, :__changed__, :element])
    assigns = Enum.into(assigns, %{attrs: attrs})

    ~H"""
    <button {@attrs}><%= render_slot(@inner_block) %></button>
    """
  end

  def maybe_show_photographer_logo?(assigns) do
    assigns = Enum.into(assigns, %{heading_class: "", logo_class: ""})

    ~H"""
    <%= case logo_url(@organization) do %>
      <% nil -> %>
        <h1 class="pt-3 text-3xl font-light font-client text-base-300 mb-2 #{@heading_class}">
          <%= @organization.name %>
        </h1>
      <% url -> %>
        <img class="h-20 #{@logo_class}" src={url} />
    <% end %>
    """
  end

  def ok(socket), do: {:ok, socket}
  def ok(socket, opts), do: {:ok, socket, opts}
  def noreply(socket), do: {:noreply, socket}
  def reply(socket, payload), do: {:reply, payload, socket}

  def testid(id) do
    if Application.get_env(:todoplace, :render_test_ids) do
      %{"data-testid" => id}
    else
      %{}
    end
  end

  def classes(nil), do: ""
  def classes(%{} = optionals), do: classes([], optionals)
  def classes([{_k, _v} | _] = optionals), do: classes([], Map.new(optionals))
  def classes(["" <> _constant | _] = constants), do: classes(constants, %{})

  def classes(nil, optionals), do: classes([], optionals)
  def classes("" <> constant, optionals), do: classes([constant], optionals)

  def classes(constants, optionals) do
    [
      constants,
      optionals
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(&elem(&1, 0))
    ]
    |> Enum.concat()
    |> Enum.join(" ")
  end

  defp path_active?(
         %{
           view: socket_view,
           router: router,
           host_uri: %{host: host}
         },
         socket_live_action,
         path
       ),
       do:
         match?(
           %{phoenix_live_view: {view, live_action, _, _}}
           when view == socket_view and live_action == socket_live_action,
           Phoenix.Router.route_info(router, "GET", path, host)
         )

  defp is_active(assigns) do
    ~H"""
    <%= render_slot(@inner_block, path_active?(@socket, @live_action, @path)) %>
    """
  end

  def nav_link(assigns) do
    assigns =
      assigns
      |> Enum.into(%{
        active_class: nil,
        target: nil
      })

    ~H"""
    <.is_active :let={active} socket={@socket} live_action={@live_action} path={@to}>
      <%= if String.starts_with?(@to, "/") do %>
        <.link
          navigate={@to}
          title={@title}
          class={classes(@class, %{@active_class => active})}
          {if @target, do: [target: @target], else: []}
        >
          <%= render_slot(@inner_block, active) %>
        </.link>
      <% else %>
        <a href={@to} class={@class}>
          <%= render_slot(@inner_block, active) %>
        </a>
      <% end %>
    </.is_active>
    """
  end

  def live_link(%{} = assigns) do
    {to, assigns} = Map.pop(assigns, :to)
    assigns = assign(assigns, :navigate, to)

    ~H"""
    <.link {assigns |> Map.drop([:__changed__, :inner_block]) |> Enum.to_list()}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  def crumbs(assigns) do
    assigns = Enum.into(assigns, %{class: "text-xs text-base-250"})

    ~H"""
    <div class={@class} {testid("crumbs")}>
      <%= for crumb <- Enum.slice(@crumb, 0..-2) do %>
        <.live_link {crumb}><%= render_slot(crumb) %></.live_link>
        <.icon name="forth" class="inline-block w-2 h-2 stroke-current stroke-2" />
      <% end %>
      <span class="font-semibold"><%= render_slot(List.last(@crumb)) %></span>
    </div>
    """
  end

  @job_type_colors %{
    "blue" => {"bg-blue-planning-100", "border-blue-planning-300", "bg-blue-planning-300"},
    "black" => {"bg-base-200", "border-base-300", "bg-base-300"}
  }
  def job_type_option(assigns) do
    assigns =
      Enum.into(assigns, %{disabled: false, class: "", color: "blue", override_global: nil})

    {bg_light, border_dark, bg_dark} = @job_type_colors |> Map.get(assigns.color)

    assigns =
      Enum.into(assigns, %{
        bg_light: bg_light,
        border_dark: border_dark,
        bg_dark: bg_dark
      })

    ~H"""
    <label class={
      classes(
        "flex items-center p-2 border rounded-lg font-semibold text-sm leading-tight sm:text-base #{@class}",
        %{
          "#{@border_dark} #{@bg_light}" => @checked,
          "cursor-not-allowed pointer-events-none" => @disabled,
          "hover:#{@bg_light}/60 cursor-pointer" => !@disabled
        }
      )
    }>
      <input
        class="hidden"
        type={@type}
        name={@name}
        value={@job_type}
        checked={@checked}
        disabled={@disabled}
      />

      <div
        testid={@job_type}
        class={
          classes(
            "flex items-center justify-center w-7 h-7 ml-1 mr-3 rounded-full flex-shrink-0",
            %{"#{@bg_dark} text-white" => @checked, "bg-base-200" => !@checked}
          )
        }
      >
        <.icon name={@job_type} class="fill-current" width="14" height="14" />
      </div>

      <%= if @override_global && @job_type == "global" do %>
        <%= @override_global %>
      <% else %>
        <%= dyn_gettext(@job_type) %>
      <% end %>
    </label>
    """
  end

  def custom_checkbox(assigns) do
    assigns =
      Enum.into(assigns, %{disabled: false, class: "", color: "blue", override_global: nil})

    {bg_light, border_dark, bg_dark} = @job_type_colors |> Map.get(assigns.color)

    assigns =
      Enum.into(assigns, %{
        bg_light: bg_light,
        border_dark: border_dark,
        bg_dark: bg_dark,
        icon: nil
      })

    ~H"""
    <label class={
      classes(
        "flex items-center justify-center p-2 border rounded-lg font-semibold text-sm leading-tight sm:text-base #{@class}",
        %{
          "#{@border_dark} #{@bg_light}" => @checked,
          "cursor-not-allowed pointer-events-none" => @disabled,
          "hover:#{@bg_light}/60 cursor-pointer" => !@disabled
        }
      )
    }>
      <input
        class="hidden"
        type={@type}
        name={@name}
        value={@job_type}
        checked={@checked}
        disabled={@disabled}
      />

      <div
        :if={@icon}
        testid={@job_type}
        class={
          classes(
            "flex items-center justify-center w-7 h-7 ml-1 mr-3 rounded-full flex-shrink-0",
            %{"#{@bg_dark} text-white" => @checked, "bg-base-200" => !@checked}
          )
        }
      >
        <.icon name={@icon} class="fill-current" width="14" height="14" />
      </div>

      <%= if @override_global && @job_type == "global" do %>
        <%= @override_global %>
      <% else %>
        <%= dyn_gettext(@job_type) %>
      <% end %>
    </label>
    """
  end

  @badge_colors %{
    filled: %{
      gray: "rounded bg-gray-100",
      blue: "rounded bg-blue-planning-100 text-blue-planning-300 group-hover:bg-white",
      green: "rounded bg-green-finances-100 text-green-finances-300",
      red: "rounded bg-red-sales-100 text-red-sales-300"
    },
    outlined: %{
      gray: "border border-base-250 text-base-250",
      blue: "border border-blue-planning-300 text-blue-planning-300 group-hover:bg-white",
      green: "border border-green-finances-300 text-green-finances-300",
      red: "border border-red-sales-300 text-red-sales-300"
    }
  }

  def badge(%{color: color} = assigns) do
    badge_mode = assigns |> Map.get(:mode, :filled)

    assigns =
      assigns
      |> Map.put(:color_style, @badge_colors |> Map.get(badge_mode) |> Map.get(color))
      |> Enum.into(%{class: ""})

    ~H"""
    <span role="status" class={"px-2 py-0.5 text-xs font-semibold #{@color_style} #{@class}"}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  def filesize(byte_size) when is_integer(byte_size),
    do: Size.humanize!(byte_size, spacer: "")

  def to_integer(lst) when is_list(lst), do: lst |> Enum.map(&to_integer(&1))

  def to_integer(int) when is_integer(int), do: int

  def to_integer(bin) when is_binary(bin),
    do: if(String.length(bin) > 0, do: String.to_integer(bin), else: nil)

  def to_integer(_), do: nil

  def blank?(""), do: true

  def blank?(nil), do: true

  def blank?(str), do: if(String.trim(str) == "", do: true, else: false)

  def display_cover_photo(%{cover_photo: %{id: photo_id}}),
    do: %{
      style:
        "background-image: url('#{Todoplace.Galleries.Workers.PhotoStorage.path_to_url(photo_id)}')"
    }

  def display_cover_photo(_), do: %{}

  defdelegate preview_url(photo), to: Todoplace.Photos
  defdelegate preview_url(photo, opts), to: Todoplace.Photos

  def initials_circle(assigns) do
    assigns =
      assigns
      |> Enum.into(%{class: "text-sm text-base-300 bg-gray-100 w-9 h-9 pb-0.5", style: nil})

    ~H"""
    <div style={@style} class={"#{@class} flex flex-col items-center justify-center rounded-full"}>
      <%= Todoplace.Accounts.User.initials(@user) %>
    </div>
    """
  end

  def show_intro?(current_user, intro_id),
    do: current_user |> Onboardings.show_intro?(intro_id) |> inspect()

  def intro(current_user, intro_id) do
    [
      phx_hook: "IntroJS",
      data_intro_show: show_intro?(current_user, intro_id),
      id: intro_id
    ]
  end

  def tooltip(assigns) do
    assigns =
      assigns
      |> Map.put(:rest, Map.drop(assigns, [:content, :class]))
      |> Enum.into(%{class: "", id: nil, inner_block: nil})

    ~H"""
    <span
      class={"inline-block relative cursor-pointer z-0 #{@class}"}
      data-hint={"#{@content}"}
      data-hintposition="middle-middle"
      phx-hook="Tooltip"
      id={@id}
    >
      <%= if @inner_block do %>
        <%= render_slot(@inner_block) %>
      <% end %>
      <.icon
        name="tooltip"
        class="inline-block w-4 h-4 mr-2 rounded-sm fill-current text-blue-planning-300"
      />
    </span>
    """
  end

  def empty_state_base(assigns) do
    assigns =
      assigns
      |> Enum.into(%{
        wrapper_class: "",
        cta_class: "",
        headline: "",
        body: "",
        eyebrow_text: "",
        third_party_padding: nil,
        inner_block: nil,
        external_video_link: nil,
        close_event: nil,
        show_dismiss: true
      })

    ~H"""
    <div class={"grid grid-cols-1 md:grid-cols-2 md:gap-20 gap-8 items-center md:pb-0 pb-8 relative #{@wrapper_class}"}>
      <%= if @close_event do %>
        <button
          {testid("intro-state-close-button")}
          class="w-8 h-8 xs:w-10 xs:h-10 z-10 absolute right-5 top-5 xs:right-3 xs:top-3 bg-base-300 text-white p-2 xs:p-3 border-transparent hover:border-blue-planning-300/60 focus:ring-blue-planning-300/70 focus:ring-opacity-75 rounded-lg cursor-pointer transition-colors"
          phx-click={@close_event}
          title="dismiss intro"
        >
          <.icon name="close-x" class="h-full w-full stroke-current stroke-3" />
        </button>
      <% end %>
      <div>
        <div
          style={"position: relative; padding-bottom: #{@third_party_padding}; height: 0;"}
          class="shadow-xl rounded"
        >
          <%= if Application.get_env(:todoplace, :show_arcade_tours) do %>
            <iframe
              src={@tour_embed}
              frameborder="0"
              loading="lazy"
              webkitallowfullscreen
              mozallowfullscreen
              allowfullscreen
              style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;"
            >
            </iframe>
          <% end %>
        </div>
        <h6 class="uppercase text-base-250 text-center my-4 text-xs tracking-widest">
          <%= @eyebrow_text %>
        </h6>
      </div>
      <div class="md:max-w-md">
        <h1 class="text-2xl md:text-5xl font-bold mb-4"><%= @headline %></h1>
        <p class="text-base-250 text-xl"><%= @body %></p>
        <div class={"flex flex-wrap md:flex-nowrap items-center md:justify-start justify-center gap-6 mt-4 mb-8 sm:mb-0 #{@cta_class}"}>
          <%= if @inner_block do %>
            <%= render_slot(@inner_block) %>
            <%= if @external_video_link do %>
              <a
                class="underline text-blue-planning-300 flex gap-3 items-center flex-shrink-0"
                href={@external_video_link}
                target="_blank"
                rel="noopener"
              >
                Video tour <.icon name="external-link" class="h-4 w-4 stroke-current stroke-1" />
              </a>
            <% end %>
            <%= if @show_dismiss do %>
              <button
                class="underline text-blue-planning-300 flex gap-3 items-center flex-shrink-0"
                type="button"
                phx-click={@close_event}
                title="dismiss intro"
              >
                Dismiss
              </button>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # def handle_event(
  #       "intro_js",
  #       %{"action" => action, "intro_id" => intro_id},
  #       %{assigns: %{current_user: current_user}} = socket
  #     ) do
  #   socket
  #   |> assign(current_user: Onboardings.save_intro_state(current_user, intro_id, action))
  #   |> noreply()
  # end

  def shoot_location(%{address: address, location: location}),
    do: address || location |> Atom.to_string() |> dyn_gettext()

  def is_mobile(socket, params) do
    is_mobile = Map.get(params, "is_mobile", get_connect_params(socket)["isMobile"])

    socket
    |> assign(
      is_mobile: if(is_binary(is_mobile), do: String.to_existing_atom(is_mobile), else: is_mobile)
    )
  end

  def get_brand_link_icon("link_" <> _), do: "anchor"
  def get_brand_link_icon(link_id), do: link_id

  def is_custom_brand_link("link_" <> _), do: true
  def is_custom_brand_link(_), do: false

  def remove_cache(user_id, _gallery_id) do
    TodoplaceWeb.UploaderCache.delete(user_id)
  end

  def stripe_checkout(%{assigns: %{proposal: proposal, job: job}} = socket) do
    payment = PaymentSchedules.unpaid_payment(job)

    case PaymentSchedules.checkout_link(proposal, payment,
           # manually interpolate here to not encode the brackets
           success_url: "#{BookingProposal.url(proposal.id)}?session_id={CHECKOUT_SESSION_ID}",
           cancel_url: BookingProposal.url(proposal.id),
           metadata: %{"paying_for" => payment.id}
         ) do
      {:ok, url} ->
        socket |> redirect(external: url)

      {:error, error} ->
        Logger.error(error)
        socket |> put_flash(:error, "Couldn't redirect to stripe. Please try again")
    end
  end

  def finish_booking(%{assigns: %{proposal: proposal}} = socket) do
    case PaymentSchedules.mark_as_paid(proposal, TodoplaceWeb.Helpers) do
      {:ok, _} ->
        send(self(), {:update_payment_schedules})
        socket

      {:error, _} ->
        socket |> put_flash(:error, "Couldn't finish booking")
    end
  end

  def date_formatter(nil), do: nil

  def date_formatter(date),
    do:
      "#{Timex.month_name(date.month)} #{date.day}#{cond do
        date.day in [1, 21, 31] -> "st"
        date.day in [2, 22] -> "nd"
        date.day == 3 -> "rd"
        true -> "th"
      end}, #{date.year}"

  def date_formatter(date, :day),
    do:
      "#{Timex.day_name(Timex.weekday(date, :monday))}, #{Timex.month_name(date.month)} #{date.day}#{cond do
        date.day in [1, 21, 31] -> "st"
        date.day in [2, 22] -> "nd"
        date.day == 3 -> "rd"
        true -> "th"
      end}, #{date.year}"

  def format_date_via_type(_, _ \\ "MM DD, YY")

  def format_date_via_type(%DateTime{} = datetime, type),
    do: DateTime.to_date(datetime) |> format_date_via_type(type)

  def format_date_via_type(%Date{} = date, type) do
    case type do
      "MM/DD/YY" ->
        [date.month, date.day, date.year]
        |> Enum.map(&to_string/1)
        |> Enum.map_join("/", &String.pad_leading(&1, 2, "0"))

      _ ->
        "#{Timex.month_name(date.month)} #{date.day}, #{date.year}"
    end
  end

  def base_url(:support), do: Application.get_env(:todoplace, :support_url)
  def base_url(:marketing), do: Application.get_env(:todoplace, :marketing_url)
  def base_url(), do: Application.get_env(:todoplace, :app_url)

  @doc """
  Format datetime as per given type, it aslo accepts timezone to convert datetime accordingly
  """
  def format_datetime_via_type(%DateTime{} = datetime, time_zone, type \\ "MM DD, YY") do
    datetime = DateTime.shift_zone!(datetime, time_zone)
    date = DateTime.to_date(datetime)

    time =
      datetime
      |> DateTime.to_time()
      |> Calendar.strftime("%I:%M %p")

    format_date_via_type(date, type) <> " @ #{time}"
  end
end
