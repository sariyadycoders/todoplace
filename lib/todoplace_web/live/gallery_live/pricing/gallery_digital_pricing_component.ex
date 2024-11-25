defmodule TodoplaceWeb.GalleryLive.Pricing.GalleryDigitalPricingComponent do
  @moduledoc false

  use TodoplaceWeb, :live_component

  import TodoplaceWeb.LiveModal, only: [close_x: 1, footer: 1]
  import Todoplace.Utils, only: [products_currency: 0]

  import TodoplaceWeb.PackageLive.Shared,
    only: [
      current: 1,
      check?: 2,
      get_field: 2
    ]

  alias Ecto.Changeset

  alias Todoplace.{
    GlobalSettings,
    Galleries.GalleryDigitalPricing,
    Packages.Download,
    Packages.PackagePricing,
    Currency
  }

  @impl true
  def update(%{current_user: current_user, gallery: gallery} = assigns, socket) do
    currency = Currency.for_gallery(gallery)

    socket
    |> assign(assigns)
    |> assign(:currency, currency)
    |> assign(:currency_symbol, Money.Currency.symbol!(currency))
    |> assign_new(:package_pricing, fn -> %PackagePricing{} end)
    |> assign(:email_error, [])
    |> assign(:email_input, nil)
    |> assign(:email_value, nil)
    |> assign(:email_list, gallery.job.client.email)
    |> assign(global_settings: GlobalSettings.get(current_user.organization_id))
    |> assign_changeset(%{}, nil)
    |> ok()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="modal">
      <.close_x />

      <div class="flex flex-row">
        <h1 class="mt-2 mb-4 text-3xl font-bold mr-6">Edit digital pricing & credits</h1>
        <div class="flex flex-row items-center">
          <div class="flex items-center justify-center flex-shrink-0 w-8 h-8 rounded-full bg-blue-planning-300">
            <.icon name="gallery-camera" class="w-4 h-4 text-white fill-current" />
          </div>
          <div class="flex flex-col ml-2">
            <p><b>Gallery: </b><%= @gallery.name %></p>
          </div>
        </div>
      </div>

      <.form
        :let={f}
        for={@changeset}
        phx-change={:validate}
        phx-submit={:submit}
        phx-target={@myself}
        id={"form-digital-pricing-gallery-#{@gallery.id}"}
      >
        <%= if @currency in products_currency() do %>
          <div class="border border-solid mt-6 p-6 rounded-lg">
            <% p = to_form(@package_pricing) %>
            <div class="mt-9 md:mt-1" {testid("print")}>
              <h2 class="mb-2 text-xl font-bold justify-self-start sm:mr-4 whitespace-nowrap">
                Professional Print Credit
              </h2>
              <p class="text-base-250">
                Print Credits allow your clients to order professional prints and products from your gallery.
              </p>
            </div>

            <div class="mt-4 font-normal text-base leading-6">
              <div class="mt-2">
                <label class="flex items-center font-bold">
                  <%= radio_button(p, :is_enabled, true, class: "w-5 h-5 mr-2.5 radio") %> Gallery includes Print Credits
                </label>
                <div class="flex items-center mt-2 gap-4 ml-7">
                  <%= if p |> current() |> Map.get(:is_enabled) do %>
                    <div class="flex flex-col">
                      <div class="flex flex-row items-center w-auto border border-blue-planning-300 rounded-lg relative">
                        <%= input(f, :print_credits,
                          placeholder: "#{@currency_symbol}0.00",
                          class:
                            "sm:w-32 w-full bg-white px-1 border-none text-lg sm:mt-0 font-normal text-center",
                          phx_debounce: 1000,
                          phx_hook: "PriceMask",
                          data_currency: @currency_symbol
                        ) %>
                      </div>
                      <%= text_input(f, :currency,
                        value: @currency,
                        class: "sm:w-32 form-control text-base-250 border-none",
                        phx_debounce: "500",
                        maxlength: 3,
                        autocomplete: "off"
                      ) %>
                    </div>
                    <div class="flex items-center text-base-250">
                      <%= label_for(f, :print_credits,
                        label: "pulled from your package revenue",
                        class: "font-normal"
                      ) %>
                    </div>
                  <% end %>
                </div>
              </div>

              <label class="flex mt-3 font-bold">
                <%= radio_button(p, :is_enabled, false, class: "w-5 h-5 mr-2.5 radio mt-0.5") %> Gallery does not include Print Credits
              </label>
            </div>
          </div>

          <hr class="block w-full mt-6 sm:hidden" />
        <% end %>
        <div class="border border-solid mt-6 p-6 rounded-lg">
          <% d = to_form(@download_changeset) %>
          <div class="mt-9 md:mt-1" {testid("download")}>
            <h2 class="mb-2 text-xl font-bold justify-self-start sm:mr-4 whitespace-nowrap">
              Digital Collection
            </h2>
            <p class="text-base-250">High-Resolution Digital Images available via download.</p>
          </div>
          <div class="flex flex-col md:flex-row w-full mt-3">
            <div class="flex flex-col">
              <label class="flex">
                <%= radio_button(d, :status, :limited, class: "w-5 h-5 mr-2 radio mt-0.5") %>
                <p>
                  <b>Clients don’t have to pay for some Digital Images </b><i>(Charge for some Digital Images)</i>
                </p>
              </label>

              <%= if get_field(d, :status) == :limited do %>
                <div class="flex flex-col mt-1">
                  <div class="flex flex-row items-center">
                    <%= input(
                      d,
                      :count,
                      type: :number_input,
                      phx_debounce: 200,
                      step: 1,
                      min: 0,
                      placeholder: "0",
                      class: "mt-3 w-full sm:w-32 text-lg text-center md:ml-7"
                    ) %>
                    <span class="ml-2 text-base-250">included in the package</span>
                  </div>
                </div>
              <% end %>

              <label class="flex mt-3">
                <%= radio_button(d, :status, :none, class: "w-5 h-5 mr-2 radio mt-0.5") %>
                <p>
                  <b>Clients have to pay for all Digital images </b><i>(Charge for all Digital Images)</i>
                </p>
              </label>
              <label class="flex mt-3">
                <%= radio_button(d, :status, :unlimited, class: "w-5 h-5 mr-2 radio mt-0.5") %>
                <p>
                  <b>Clients have Unlimited Digital Images </b><i>(Do not charge for any Digital Image)</i>
                </p>
              </label>
            </div>
            <div class="my-8 border-t lg:my-0 lg:mx-8 lg:border-t-0 lg:border-l border-base-200">
            </div>
            <%= if get_field(d, :status) in [:limited, :none] do %>
              <div class="ml-7 mt-3">
                <h3 class="font-bold">Pricing Options</h3>
                <p class="mb-3 text-base-250">
                  The following digital image pricing is set in your Global Gallery Settings
                </p>

                <div class="flex flex-col justify-between mt-3 sm:flex-row ">
                  <div class="w-full sm:w-auto">
                    <label class="flex font-bold items-center">
                      <%= checkbox(d, :is_custom_price, class: "w-5 h-5 mr-2.5 checkbox") %>
                      <span>Change my per <i>Digital Image</i> price for this package</span>
                    </label>
                    <span class="font-normal ml-7 text-base-250">
                      (<%= input_value(d, :each_price) %>/each)
                    </span>
                    <%= if check?(d, :is_custom_price) do %>
                      <div class="flex flex-row items-center mt-3 lg:ml-7">
                        <div class="flex flex-row items-center w-auto border border-blue-planning-300 rounded-lg relative">
                          <%= input(d, :each_price,
                            placeholder: "#{@currency_symbol}50.00",
                            class:
                              "sm:w-32 w-full px-1 border-none text-lg sm:mt-0 font-normal text-center",
                            phx_hook: "PriceMask",
                            data_currency: @currency_symbol
                          ) %>
                        </div>
                        <%= error_tag(d, :each_price, class: "text-red-sales-300 text-sm ml-2") %>
                        <span class="ml-3 text-base-250"> per image </span>
                      </div>
                      <%= text_input(d, :currency,
                        value: @currency,
                        class: "form-control border-none text-base-250 lg:ml-7",
                        phx_debounce: "500",
                        maxlength: 3,
                        autocomplete: "off"
                      ) %>
                    <% end %>
                  </div>
                </div>

                <label class="flex items-center mt-3 font-bold">
                  <%= checkbox(d, :is_buy_all, class: "w-5 h-5 mr-2.5 checkbox") %>
                  <span>Offer a <i>Buy Them All</i> price for this package</span>
                </label>

                <%= if check?(d, :is_buy_all) do %>
                  <div class="flex flex-row items-center mt-3 lg:ml-7">
                    <div class="flex flex-row items-center w-auto border border-blue-planning-300 rounded-lg relative">
                      <%= input(d, :buy_all,
                        placeholder: "#{@currency_symbol}750.00",
                        class: "sm:w-32 w-full border-none text-lg sm:mt-0 font-normal text-center",
                        phx_hook: "PriceMask",
                        data_currency: @currency_symbol
                      ) %>
                    </div>
                    <%= error_tag(d, :buy_all, class: "text-red-sales-300 text-sm ml-2") %>
                    <span class="ml-3 text-base-250"> for all images </span>
                  </div>
                  <%= text_input(d, :currency,
                    value: @currency,
                    class: "form-control border-none lg:ml-7 text-base-250",
                    phx_debounce: "500",
                    maxlength: 3,
                    autocomplete: "off"
                  ) %>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <hr class="block w-full mt-6 sm:hidden" />

        <div class="border border-solid mt-6 p-6 rounded-lg">
          <div class="mt-9 md:mt-1" {testid("email_list")}>
            <h2 class="mb-2 text-xl font-bold justify-self-start sm:mr-4 whitespace-nowrap">
              Restrict <%= if @currency in products_currency(), do: "Print & " %>Digital Image Credits
            </h2>
            <p class="text-base-250">
              Set who can use the <%= if @currency in products_currency(), do: "print and " %>digital image credits here via their email. Your client will be added automatically.
            </p>
          </div>

          <div class="mt-4 font-normal text-base leading-6">
            <label class="flex mt-3 font-bold">Enter email</label>
            <div class="flex items-center gap-4">
              <input
                type="text"
                class="form-control text-input rounded"
                id="email_input"
                name="email"
                value={@email_value}
                phx-debounce="500"
                spellcheck="false"
                placeholder="enter email..."
              />
              <button
                class="btn-primary"
                type="button"
                title="Add email"
                phx-target={@myself}
                phx-click="add-email"
                disabled={
                  Enum.any?(@email_error, fn error -> error == "please enter valid email" end) ||
                    is_nil(@email_input)
                }
              >
                Add email
              </button>
            </div>
            <span
              {testid("email-error")}
              class={classes("text-red-sales-300 text-sm", %{"hidden" => Enum.empty?(@email_error)})}
            >
              <%= if length(@email_error) > 0, do: hd(@email_error) %>
            </span>
          </div>

          <div class="mt-4 grid grid-cols-2 gap-x-10">
            <%= for(email <- @email_list) do %>
              <a class="flex items-center mt-2 hover:cursor-pointer">
                <.icon name="envelope" class="text-blue-planning-300 w-4 h-4" />
                <span class="text-base-250 ml-2">
                  <%= email %> <%= if @gallery.job.client.email == email, do: "(client)" %>
                </span>
                <button
                  title="Trash"
                  type="button"
                  phx-target={@myself}
                  phx-click="delete-email"
                  phx-value-email={email}
                  class="flex items-center px-2 py-2 bg-gray-100 rounded-lg hover:bg-red-sales-100 hover:font-bold ml-auto"
                >
                  <.icon name="trash" class="inline-block w-4 h-4 fill-current text-red-sales-300" />
                </button>
              </a>
            <% end %>
          </div>
          <hr class="block w-full mt-2" />
        </div>

        <.footer class="pt-10">
          <button
            class="btn-primary"
            title="Save"
            type="submit"
            disabled={
              !@changeset.valid? ||
                Enum.any?(@email_error, fn error -> error == "atleast one email required" end)
            }
          >
            Save
          </button>
        </.footer>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event(
        event,
        params,
        %{assigns: %{currency: currency, currency_symbol: currency_symbol}} = socket
      )
      when event in ~w(validate submit) and not is_map_key(params, "parsed?") do
    __MODULE__.handle_event(
      event,
      Todoplace.Currency.parse_params_for_currency(
        params,
        {currency_symbol, currency}
      ),
      socket
    )
  end

  @impl true
  def handle_event(
        "validate",
        %{"_target" => ["email"], "email" => email},
        %{assigns: %{email_error: email_error}} = socket
      ) do
    email =
      email
      |> String.downcase()
      |> String.trim()

    if String.match?(email, Todoplace.Accounts.User.email_regex()) do
      socket
      |> assign(:email_error, List.delete(email_error, "please enter valid email"))
      |> assign(:email_value, email)
      |> assign(:email_input, email)
    else
      socket
      |> assign(
        :email_error,
        ["please enter valid email" | email_error] |> Enum.uniq()
      )
      |> assign(:email_input, nil)
      |> assign(:email_value, email)
    end
    |> noreply()
  end

  @impl true
  def handle_event("validate", params, socket) do
    socket |> assign_changeset(params) |> noreply()
  end

  @impl true
  def handle_event(
        "add-email",
        _,
        %{assigns: %{email_list: email_list, email_input: email, changeset: changeset}} = socket
      ) do
    updated_email_list = email_list ++ [email]

    socket
    |> assign(:email_list, updated_email_list)
    |> assign(:email_value, nil)
    |> assign(:email_input, nil)
    |> assign(:email_error, [])
    |> assign(:changeset, Changeset.put_change(changeset, :email_list, updated_email_list))
    |> noreply()
  end

  @impl true
  def handle_event(
        "delete-email",
        %{"email" => email},
        %{assigns: %{email_list: email_list, changeset: changeset, email_error: email_error}} =
          socket
      ) do
    updated_email_list = List.delete(email_list, email)

    socket
    |> assign(:email_list, updated_email_list)
    |> assign(
      :email_error,
      if(Enum.empty?(updated_email_list),
        do: ["atleast one email required" | email_error],
        else: email_error
      )
    )
    |> assign(:changeset, Changeset.put_change(changeset, :email_list, updated_email_list))
    |> noreply()
  end

  @impl true
  def handle_event("submit", _params, %{assigns: %{changeset: changeset}} = socket) do
    send(socket.parent_pid, {:update, %{changeset: changeset}})

    socket
    |> noreply()
  end

  defp assign_changeset(
         %{
           assigns:
             %{gallery: gallery, global_settings: global_settings, currency: currency} = assigns
         } = socket,
         params,
         action \\ :validate
       ) do
    download_params = Map.get(params, "download", %{}) |> Map.put("step", :pricing)

    download_changeset =
      gallery.gallery_digital_pricing
      |> Map.put(:currency, currency)
      |> Download.from_package(global_settings)
      |> Download.changeset(download_params, Map.get(assigns, :download_changeset))
      |> Map.put(:action, action)

    download = current(download_changeset)

    package_pricing_changeset =
      assigns.package_pricing
      |> PackagePricing.changeset(
        Map.get(params, "package_pricing", gallery_pricing_params(gallery))
      )

    digital_pricing_params =
      params
      |> Map.get("gallery_digital_pricing", %{})
      |> Map.merge(%{
        "download_count" => Download.count(download),
        "download_each_price" => Download.each_price(download, currency),
        "buy_all" => Download.buy_all(download),
        "status" => download.status
      })

    digital_pricing_params =
      if Changeset.get_field(package_pricing_changeset, :is_enabled),
        do: digital_pricing_params,
        else: digital_pricing_params |> Map.put("print_credits", Money.new(0, currency))

    changeset =
      GalleryDigitalPricing.changeset(
        if(gallery.gallery_digital_pricing,
          do: gallery.gallery_digital_pricing,
          else: %GalleryDigitalPricing{}
        ),
        digital_pricing_params
      )
      |> Map.put(:action, action)

    socket
    |> assign(
      changeset: changeset,
      email_list: Changeset.get_field(changeset, :email_list),
      package_pricing: package_pricing_changeset,
      download_changeset: download_changeset
    )
  end

  defp gallery_pricing_params(nil), do: %{}

  defp gallery_pricing_params(gallery) do
    case gallery.gallery_digital_pricing |> Map.get(:print_credits) do
      %Money{} = value -> %{is_enabled: Money.positive?(value)}
      _ -> %{is_enabled: false}
    end
  end
end
