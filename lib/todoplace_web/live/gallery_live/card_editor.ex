defmodule TodoplaceWeb.GalleryLive.CardEditor do
  @moduledoc """
    clients can filter and choose a card design to customize in WHCC
  """
  use TodoplaceWeb, live_view: [layout: "live_gallery_client"]

  import TodoplaceWeb.GalleryLive.Shared,
    only: [
      assign_cart_count: 2,
      customize_and_buy_product: 4,
      assign_checkout_routes: 1,
      get_client_by_email: 1,
      is_photographer_view: 1,
      credits_available_mobile_header: 1
    ]

  import Todoplace.Designs, only: [load_occasion: 1, occasion_designs_query: 1, occasions: 0]

  import Ecto.Query, only: [from: 2]
  alias Todoplace.{Repo, Designs.Filter}

  @per_page 16

  @impl true
  def mount(_, _, %{assigns: %{gallery: gallery, client_email: client_email} = assigns} = socket) do
    gallery = Todoplace.Repo.preload(gallery, [:gallery_digital_pricing, :organization])

    gallery =
      Map.put(
        gallery,
        :credits_available,
        (client_email && client_email in gallery.gallery_digital_pricing.email_list) ||
          is_photographer_view(assigns)
      )

    organization =
      gallery
      |> Map.get(:organization)

    socket
    |> assign(gallery: gallery)
    |> assign(organization: organization)
    |> assign(open_profile_logout?: false)
    |> assign(credits_available: gallery.credits_available)
    |> assign(gallery_client: get_client_by_email(assigns))
    |> assign_cart_count(gallery)
    |> assign(
      update: "init",
      filter: nil,
      occasion: nil,
      show_filter_form: false,
      filter_applied?: false,
      toggle_arrows?: false
    )
    |> assign_new(:album, fn -> nil end)
    |> assign_checkout_routes()
    |> ok(temporary_assigns: [designs: []])
  end

  @impl true
  def handle_params(
        %{"occasion_id" => occasion_id} = params,
        _,
        socket
      ),
      do:
        socket
        |> update(:occasion, fn
          %{id: ^occasion_id} = occasion -> occasion
          _ -> load_occasion(occasion_id)
        end)
        |> assign(page: 0)
        |> update(:update, fn
          "init" -> "append"
          _ -> "replace"
        end)
        |> update(
          :filter,
          &(case &1 do
              nil -> occasion_id |> occasion_designs_query() |> Filter.load()
              filter -> filter
            end
            |> Filter.update(Map.get(params, "filter", %{})))
        )
        |> assign(:filter_applied?, Map.get(params, "filter", %{}) != %{})
        |> fetch()
        |> noreply()

  def handle_params(_, _, socket),
    do: socket |> assign(occasion: nil, filter: nil, occasions: occasions()) |> noreply()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative mx-auto max-w-screen-xl">
      <div class="fixed top-0 md:px-6 px-2 max-w-screen-xl w-full z-40 bg-white">
        <.live_component
          module={TodoplaceWeb.GalleryLive.ClientMenuComponent}
          id={@gallery.id}
          cart_count={@cart_count}
          live_action={@live_action}
          gallery={@gallery}
          album={@album}
          is_finals={@album && @album.is_finals}
          client_email={@client_email}
          credits_available={@credits_available}
        />
      </div>

      <.credits_available_mobile_header
        organization={@organization}
        open_profile_logout?={@open_profile_logout?}
        credits_available={@credits_available}
        client_email={@client_email}
        gallery={@gallery}
        socket={@socket}
      />

      <hr />
      <.step {assigns} />
    </div>
    """
  end

  # TODO: handle me (checkout_routes)
  # choose occasion
  defp step(%{occasion: nil} = assigns) do
    ~H"""
    <div class="px-6 pt-5 mx-auto lg:pt-10 max-w-screen-xl">
      <div class="sticky top-10 lg:top-20 pt-8 lg:pt-4 pb-4 z-10 bg-white max-w-screen-xl w-full">
        <nav class="pb-7 text-base-250">
          <ol class="flex items-center list-reset">
            <li>
              <.link navigate={@checkout_routes.home_page}>
                <%= if @album && @album.is_finals, do: "Album Home", else: "Gallery Home" %>
              </.link>
            </li>

            <li><.icon name="forth" class="w-2 h-2 mx-1 stroke-2" /></li>

            <li>
              <.link navigate={self_path(@socket, @gallery, @album)} class="font-bold">
                Choose occasion
              </.link>
            </li>
          </ol>
        </nav>

        <h1 class="text-2xl sm:text-4xl">
          Choose occasion
        </h1>
      </div>

      <ul class="pt-6 pb-16 grid grid-cols-2 lg:grid-cols-4 gap-6">
        <%= for occasion <- @occasions do %>
          <li>
            <.link navigate={self_path(@socket, @gallery, @album, %{"occasion_id" => occasion.id})}>
              <.img_box src={occasion.preview_url} />

              <h3 class="pt-2 text-lg capitalize"><%= occasion.name %></h3>
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp step(%{show_filter_form: true} = assigns) do
    ~H"""
    <div class="px-6 pt-5 mx-auto lg:pt-10 max-w-screen-xl">
      <div id="filters" class="absolute top-0 left-0 z-50 w-screen min-h-screen p-8 bg-base-100">
        <button phx-click="toggle-filter-form" class="block mt-6 mb-10">
          <.icon name="close-x" class="w-5 h-5 stroke-current" />
        </button>

        <.form
          :let={_f}
          for={%{}}
          as={:filter}
          method="get"
          phx-change="apply-filters"
          id="filter-form"
        >
          <.ul
            filter={@filter}
            nested_list_class="mb-8 border shadow-lg border-base-200"
            button_class="flex items-center w-full py-2 text-2xl font-semibold"
            options_icon_class="mt-3 right-10 peer-checked:text-base-300"
            ,
            is_mobile={true}
          />

          <.filter_option_pills filter={@filter} />

          <button
            type="button"
            phx-click="toggle-filter-form"
            class="flex py-2.5 mt-20 text-xl border border-base-300 justify-center items-center font-medium w-full"
          >
            Show results
          </button>
        </.form>
      </div>
    </div>
    """
  end

  # TODO: handle me (checkout_routes)
  defp step(assigns) do
    ~H"""
    <div class="px-6 pt-5 mx-auto lg:pt-10 max-w-screen-xl">
      <div class="sticky top-10 lg:top-20 pr-12 pt-9 z-10 bg-white max-w-screen-xl w-full">
        <nav class="mb-9 text-base-250">
          <ol class="flex items-center list-reset">
            <li>
              <.link navigate={@checkout_routes.home_page}>
                <%= if @album && @album.is_finals, do: "Album Home", else: "Gallery Home" %>
              </.link>
            </li>

            <li><.icon name="forth" class="w-2 h-2 mx-1 stroke-2" /></li>

            <li>
              <.link navigate={self_path(@socket, @gallery, @album)}>
                Choose occasion
              </.link>
            </li>

            <li><.icon name="forth" class="w-2 h-2 mx-1 stroke-2" /></li>

            <li>
              <.link
                navigate={self_path(@socket, @gallery, @album, %{"occasion_id" => @occasion.id})}
                class="font-bold capitalize"
              >
                <%= @occasion.name %>
              </.link>
            </li>
          </ol>
        </nav>

        <h1 class="mb-5 text-2xl capitalize sm:text-4xl">
          <%= @occasion.name %>
        </h1>

        <div class="flex items-end justify-between mb-7 lg:mb-2">
          <button
            class="flex py-2.5 px-4 text-xl border border-base-300 items-center font-medium lg:hidden"
            phx-click="toggle-filter-form"
          >
            Filters <.icon name="funnel" class="w-4 h-4 ml-3" />
          </button>

          <.filter_navbar {assigns} />
          <p class="font-medium text-base-250">
            Showing <%= @filtered_count %> of <%= @total_count %> designs
          </p>
        </div>

        <hr class="border-base-225" />

        <.form
          :let={_f}
          for={%{}}
          as={:pills}
          method="get"
          phx-change="apply-filters"
          class="pb-6 relative"
        >
          <%= for %{id: filter_id, options: options} <- @filter, %{id: option_id, checked: true} <- options do %>
            <input type="hidden" name={"filter[#{filter_id}][]"} value={option_id} />
          <% end %>

          <.filter_option_pills filter={@filter} />
        </.form>
      </div>

      <ul
        class={"relative pt-6 grid grid-cols-2 lg:grid-cols-4 gap-6 #{top(@filter_applied?)}"}
        id="design-grid"
        phx-update={@update}
        phx-hook="InfiniteScroll"
        data-page={@page}
        data-threshold="75"
      >
        <%= for {design, design_index} <- @designs |> Enum.with_index() do %>
          <li id={"design-#{design.id}"}>
            <.img_box
              src={design.preview_url}
              card_design={true}
              value={design.id}
              img_index={design_index}
              hide_next={if @toggle_arrows? == design_index, do: true, else: false}
              hide_prev={if @toggle_arrows? == design_index, do: false, else: true}
            />

            <h3 class="pt-2 text-lg"><%= design.name %></h3>
            <p class="mt-1 text-sm text-base-250"><%= photo_range_summary(design) %></p>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp top(true), do: "top-[320px] lg:pb-96 pb-[394px]"
  defp top(false), do: "top-[250px] pb-80"

  @impl true
  # if it fires but we are choosing an occasion
  def handle_event("load-more", _, %{assigns: %{occasion: nil}} = socket), do: noreply(socket)

  def handle_event("load-more", _, socket) do
    socket |> update(:page, &(&1 + 1)) |> assign(update: "append") |> fetch() |> noreply()
  end

  def handle_event(
        "profile_logout",
        _,
        %{assigns: %{open_profile_logout?: open_profile_logout?}} = socket
      ) do
    socket
    |> assign(open_profile_logout?: !open_profile_logout?)
    |> noreply()
  end

  def handle_event("apply-filters", %{"_target" => ["clear all"]}, socket) do
    __MODULE__.handle_event("apply-filters", %{}, socket)
  end

  def handle_event(
        "apply-filters",
        data,
        %{
          assigns: %{filter: filter, gallery: gallery, occasion: %{id: occasion_id}, album: album}
        } = socket
      ) do
    filter_params = filter |> Filter.update(Map.get(data, "filter", %{})) |> Filter.to_params()

    socket
    |> push_patch(
      to: self_path(socket, gallery, album, %{occasion_id: occasion_id, filter: filter_params})
    )
    |> assign(:filter_applied?, filter_params != %{})
    |> noreply()
  end

  def handle_event("toggle-open-filter", %{"is_unique" => _, "value" => filter_id}, socket) do
    socket
    |> update(:filter, &Enum.map(&1, fn f -> %{f | open: filter_id == f.id && f.open} end))
    |> assign(:update, "append")
    |> then(&__MODULE__.handle_event("toggle-open-filter", %{"value" => filter_id}, &1))
  end

  def handle_event("toggle-open-filter", %{"value" => filter_id}, socket) do
    socket |> update(:filter, &Filter.open(&1, filter_id)) |> noreply()
  end

  def handle_event("close-filter-dropdown", _, socket) do
    socket
    |> update(:filter, &Enum.map(&1, fn f -> %{f | open: false} end))
    |> assign(:update, "append")
    |> noreply()
  end

  def handle_event(
        "open-editor",
        %{"value" => design_id},
        %{assigns: %{gallery: gallery}} = socket
      ) do
    %{product: product, whcc_id: design_id} =
      Repo.get(Todoplace.Designs.designs_query(), design_id)

    photo = gallery |> Ecto.assoc(:photos) |> Repo.all() |> hd

    customize_and_buy_product(socket, product, photo, design: design_id)
  end

  def handle_event(
        "next",
        %{"value" => design_id, "img_index" => img_index},
        %{assigns: %{toggle_arrows?: toggle_arrows?}} = socket
      ) do
    socket = socket |> fetch()
    change_arrows = String.to_integer(img_index)
    show? = if change_arrows == toggle_arrows?, do: false, else: change_arrows

    item_index =
      Enum.find_index(socket.assigns.designs, fn design ->
        design.id == String.to_integer(design_id)
      end)

    new_design = Repo.one(Todoplace.Designs.single_design_back_query(design_id))

    designs = List.replace_at(socket.assigns.designs, item_index, new_design)

    socket
    |> assign(:designs, designs)
    |> assign(:toggle_arrows?, show?)
    |> noreply()
  end

  def handle_event(
        "prev",
        %{"value" => design_id, "img_index" => img_index},
        %{assigns: %{toggle_arrows?: toggle_arrows?}} = socket
      ) do
    socket = socket |> fetch()
    change_arrows = String.to_integer(img_index)
    show? = if change_arrows == toggle_arrows?, do: false, else: change_arrows

    item_index =
      Enum.find_index(socket.assigns.designs, fn design ->
        design.id == String.to_integer(design_id)
      end)

    new_design = Repo.one(Todoplace.Designs.single_design_front_query(design_id))

    designs = List.replace_at(socket.assigns.designs, item_index, new_design)

    socket
    |> assign(:designs, designs)
    |> assign(:toggle_arrows?, show?)
    |> noreply()
  end

  def handle_event("toggle-filter-form", _, socket),
    do:
      socket
      |> update(:show_filter_form, &(!&1))
      |> update(:filter, &Filter.close_all/1)
      |> assign(:update, "replace")
      |> fetch()
      |> noreply()

  # for desktop view
  defp filter_navbar(assigns) do
    ~H"""
    <.form
      :let={_f}
      for={%{}}
      as={:filter}
      method="get"
      phx-change="apply-filters"
      id="filter-form"
      class="hidden lg:block"
    >
      <nav class="bg-white">
        <div class="container flex flex-wrap justify-between items-center mx-auto">
          <div phx-click-away="close-filter-dropdown" class="w-auto">
            <.ul
              filter={@filter}
              main_list_class="flex rounded-lg flex-row space-x-4 text-sm font-medium bg-white"
              nested_list_class="absolute z-10 py-1 font-medium text-sm text-base-500 bg-white w-44 rounded divide-y divide-gray-100 shadow"
              button_class="flex justify-between items-center pr-2 font-black w-full text-base w-auto"
              options_icon_class="right-5 mt-2 peer-checked:text-black"
            />
          </div>
        </div>
      </nav>
    </.form>
    """
  end

  defp ul(assigns) do
    assigns = Enum.into(assigns, %{main_list_class: "", is_mobile: false})

    ~H"""
    <ul class={@main_list_class}>
      <%= for %{id: filter_id, name: name, options: options, open: open} <- @filter do %>
        <li>
          <button
            type="button"
            class={@button_class}
            value={filter_id}
            phx-value-is_unique={true}
            phx-click="toggle-open-filter"
          >
            <%= name %>
            <.icon
              name={if open, do: "up", else: "down"}
              class="w-2 h-2 ml-2.5 stroke-current stroke-2"
            />
          </button>
          <ul class={classes(@nested_list_class, %{"hidden" => not open})}>
            <.filter_options options={options} filter_id={filter_id} icon_class={@options_icon_class} />
          </ul>
          <%= if @is_mobile && !open do %>
            <hr class="mb-8" />
          <% end %>
        </li>
      <% end %>
    </ul>
    """
  end

  defp filter_options(assigns) do
    assigns = Map.put_new(assigns, :icon_class, "")

    ~H"""
    <%= for %{id: option_id, checked: checked} = option <- @options, dom_id = Enum.join([@filter_id, option_id], "-") do %>
      <li>
        <input
          type="checkbox"
          id={dom_id}
          name={"filter[#{@filter_id}][]"}
          value={option_id}
          checked={checked}
          class="hidden peer cursor-pointer"
        />
        <.icon
          name="checkmark"
          class={"absolute w-8 h-4 stroke-current #{!checked && 'hidden'} #{@icon_class}"}
        />

        <label for={dom_id} class="block px-5 py-3 hover:bg-base-200 peer-checked:bg-base-200">
          <.filter_option_label option={option} />
        </label>
      </li>
    <% end %>
    """
  end

  defp filter_option_label(assigns) do
    ~H"""
    <div class="flex items-center leading-snug capitalize cursor-pointer">
      <%= case @option do %>
        <% %{name: name, swatch: {r,g,b}} -> %>
          <div style={"background-color:rgb(#{r},#{g},#{b})"} class="w-4 h-4 mr-2"></div>
          <%= name %>
        <% %{name: name} -> %>
          <%= name %>
      <% end %>
    </div>
    """
  end

  defp filter_option_pills(assigns) do
    ~H"""
    <ul class="flex flex-wrap w-full" {testid("pills")}>
      <%= for %{id: filter_id, options: options} <- @filter, %{checked: true, id: option_id} = option <- options do %>
        <.filter_li class="border border-base-250 text-base-250">
          <input
            type="checkbox"
            class="hidden"
            value={option_id}
            name={"filter[remove][#{filter_id}][]"}
          />
          <.filter_option_label option={option} />
        </.filter_li>
      <% end %>
      <%= if Enum.any?(@filter, fn %{options: options} -> Enum.any?(options, & &1.checked) end) do %>
        <.filter_li class="text-base-300 cursor-pointer">
          <input type="checkbox" class="hidden" value="clear all" name="clear all" /> Clear all
        </.filter_li>
      <% end %>
    </ul>
    """
  end

  defp photo_range_summary(%{photo_slots: slots}) do
    slots
    |> slot_ranges()
    |> case do
      [] ->
        ""

      [1..1] ->
        "1 photo"

      ranges ->
        Enum.join(
          for %{first: first, last: last} <- ranges do
            case last - first do
              0 -> last
              1 -> Enum.join([first, last], ", ")
              _ -> Enum.join([first, last], "-")
            end
          end,
          ", "
        ) <> " photos"
    end
  end

  defp slot_ranges(slots),
    do:
      slots
      |> combinations()
      |> Enum.map(&Enum.sum/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> ranges()

  def combinations([values]), do: Enum.map(values, &[&1])

  def combinations([values | tail]),
    do: for(combos <- combinations(tail), value <- values, do: [value | combos])

  def ranges([head | tail]) do
    for n <- tail, reduce: [head..head] do
      [%{last: last} = range | rest] when n == last + 1 -> [range.first..n | rest]
      [range | rest] -> [n..n | [range | rest]]
    end
    |> Enum.reverse()
  end

  def ranges([]), do: []

  defp img_box(%{card_design: true, hide_next: _, hide_prev: _, img_index: _} = assigns) do
    value = Map.get(assigns, :value)

    assigns = assign(assigns, value: value)

    ~H"""
    <div class="aspect-h-1 aspect-w-1">
      <div class="relative bg-gradient-to-bl from-[#f5f6f7] to-[#ededed] flex flex-col justify-center group">
        <%= if !@hide_prev do %>
          <div
            phx-click="prev"
            phx-value-value={@value}
            phx-value-img_index={@img_index}
            class="z-30 left-0 absolute top-1/2 -translate-y-1/2 hidden group-hover:block"
          >
            <.icon name="back" class="w-6 h-6 cursor-pointer text-base-250" />
          </div>
        <% end %>
        <%= if !@hide_next do %>
          <div
            phx-click="next"
            phx-value-value={@value}
            phx-value-img_index={@img_index}
            class="z-30 right-0 absolute top-1/2 -translate-y-1/2 hidden group-hover:block"
          >
            <.icon name="forth" class="w-6 h-6 cursor-pointer text-base-250" />
          </div>
        <% end %>
        <img class="object-scale-down min-h-0 p-6 drop-shadow-md" src={@src} />
        <div
          class="absolute right-0 left-0 mx-auto bottom-2 w-[90%] btn-primary hidden group-hover:block text-center hover:cursor-pointer"
          phx-click="open-editor"
          phx-value-value={@value}
        >
          Continue with this design
        </div>
      </div>
    </div>
    """
  end

  defp img_box(assigns) do
    ~H"""
    <div class="aspect-h-1 aspect-w-1">
      <div class="bg-gradient-to-bl from-[#f5f6f7] to-[#ededed] flex flex-col justify-center">
        <img class="object-scale-down min-h-0 p-6 drop-shadow-md" src={@src} />
      </div>
    </div>
    """
  end

  defp filter_li(assigns) do
    assigns = Enum.into(assigns, %{class: ""})

    ~H"""
    <li>
      <label class={"mx-4 mt-7 first:ml-0 py-2.5 px-4 text-xl items-center justify-center font-medium flex #{@class}"}>
        <%= render_slot(@inner_block) %>
        <.icon name="close-x" class="w-3 h-3 ml-3 stroke-current stroke-[5px] cursor-pointer" />
      </label>
    </li>
    """
  end

  defp self_path(socket, gallery, album, params \\ %{})

  defp self_path(socket, _gallery, %{is_finals: true} = album, params),
    do: ~p"/album/#{album.client_link_hash}/cards?#{params}"

  defp self_path(socket, gallery, _album, params),
    do: ~p"/album/#{gallery.client_link_hash}/cards?#{params}"

  def fetch(%{assigns: %{page: page, occasion: occasion, filter: filter}} = socket) do
    occasion_designs = occasion_designs_query(occasion)
    total_count_task = Task.async(fn -> Repo.aggregate(occasion_designs, :count, :id) end)

    filtered_designs = Filter.query(occasion_designs, filter)

    designs_task = Task.async(fn -> load_designs(filtered_designs, page) end)
    filtered_count_task = Task.async(fn -> Repo.aggregate(filtered_designs, :count, :id) end)

    total_count = Task.await(total_count_task)
    filtered_count = Task.await(filtered_count_task, 10_000)
    designs = Task.await(designs_task, 10_000)

    assign(socket,
      designs: designs,
      total_count: total_count,
      filtered_count: filtered_count
    )
  end

  def load_designs(filtered_designs, page),
    do:
      from(design in Todoplace.Designs.designs_query(filtered_designs),
        limit: @per_page,
        offset: ^page * @per_page
      )
      |> Repo.all()
end
