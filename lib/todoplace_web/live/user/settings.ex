defmodule TodoplaceWeb.Live.User.Settings do
  @moduledoc false
  use TodoplaceWeb, :live_view

  alias Todoplace.{
    Accounts,
    Accounts.User,
    Accounts.User.Promotions,
    Organization,
    Onboardings,
    Packages,
    Repo,
    Subscription,
    Subscriptions,
    RewardfulAffiliate,
    Rewardful,
    Payments
  }

  import TodoplaceWeb.Gettext, only: [ngettext: 3]
  import TodoplaceWeb.Helpers, only: [days_distance: 1]

  require Logger

  @changeset_types %{current_password: :string, email: :string}

  @impl true
  def mount(_params, _session, %{assigns: %{current_user: user}} = socket) do
    %{value: black_friday_code} =
      Todoplace.AdminGlobalSettings.get_settings_by_slug("black_friday_code")

    socket
    |> assign(:current_user, Accounts.preload_settings(user))
    |> assigns_changesets()
    |> assign(:promotion_code, Subscriptions.maybe_get_promotion_code?(user))
    |> assign(:card_btn_class, "btn-primary px-9 mx-1")
    |> assign_preferred_phone_country()
    |> assign(
      :current_sale,
      Promotions.get_user_promotion_by_slug(user, black_friday_code)
    )
    |> assign(
      :sale_promotion_code,
      if(Subscriptions.maybe_return_promotion_code_id?(black_friday_code),
        do: black_friday_code,
        else: nil
      )
    )
    |> ok()
  end

  @impl true
  def handle_params(
        %{"pre_purchase" => "true", "checkout_session_id" => _},
        _uri,
        %{assigns: %{sale_promotion_code: sale_promotion_code, current_user: current_user}} =
          socket
      ) do
    Promotions.insert_or_update_promotion(current_user, %{
      slug: sale_promotion_code,
      state: :purchased,
      name: "Holiday"
    })

    Onboardings.user_update_promotion_code_changeset(current_user, %{
      onboarding: %{
        sale_promotion_code: sale_promotion_code
      }
    })
    |> Repo.update!()

    socket
    |> put_flash(:success, "Year extended!")
    |> noreply()
  end

  @impl true
  def handle_params(_params, _uri, socket), do: socket |> noreply()

  defp assigns_changesets(%{assigns: %{current_user: user}} = socket) do
    socket
    |> assign(
      case user.sign_up_auth_provider do
        :password ->
          [email_changeset: email_changeset(user), password_changeset: password_changeset(user)]

        _ ->
          [email_changeset: nil, password_changeset: nil]
      end
      |> Keyword.merge(
        submit_changed_password: false,
        sign_out: false,
        page_title: "Settings"
      )
    )
    |> assign(
      name_changeset: name_changeset(user),
      organization_name_changeset: organization_name_changeset(user),
      organization_address_changeset: organization_address_changeset(user),
      phone_changeset: phone_changeset(user),
      time_zone_changeset: time_zone_changeset(user)
    )
    |> assign_is_save_settings()
  end

  defp assigns_email_changeset(%{assigns: %{current_user: user}} = socket) do
    user = Packages.get_current_user(user.id)

    socket
    |> assign(email_changeset: email_changeset(user), current_user: user)
    |> assign_is_save_settings()
  end

  defp assigns_password_changeset(%{assigns: %{current_user: user}} = socket) do
    user = Packages.get_current_user(user.id)

    socket
    |> assign(password_changeset: password_changeset(user), current_user: user)
    |> assign_is_save_settings()
  end

  defp assigns_name_changeset(%{assigns: %{current_user: user}} = socket) do
    user = Packages.get_current_user(user.id)

    socket
    |> assign(organization_name_changeset: organization_name_changeset(user), current_user: user)
    |> assign_is_save_settings()
  end

  defp assigns_time_changeset(%{assigns: %{current_user: user}} = socket) do
    user = Packages.get_current_user(user.id)

    socket
    |> assign(time_zone_changeset: time_zone_changeset(user), current_user: user)
    |> assign_is_save_settings()
  end

  defp assigns_phone_changeset(%{assigns: %{current_user: user}} = socket) do
    user = Packages.get_current_user(user.id)

    socket
    |> assign(phone_changeset: phone_changeset(user), current_user: user)
    |> assign_is_save_settings()
  end

  defp assign_is_save_settings(
         %{
           assigns: %{
             email_changeset: nil,
             password_changeset: nil
           }
         } = socket
       ) do
    socket |> assign(is_save_settings: "false")
  end

  defp assign_is_save_settings(
         %{
           assigns: %{
             time_zone_changeset: time_zone,
             phone_changeset: phone,
             organization_name_changeset: name,
             email_changeset: email,
             password_changeset: password
           }
         } = socket
       ) do
    is_save_settings =
      if !time_zone.valid? and !phone.valid? and !name.valid? and !email.valid? and
           !password.valid? do
        "true"
      else
        "false"
      end

    socket |> assign(is_save_settings: is_save_settings)
  end

  defp email_changeset(user, params \\ %{}) do
    {user, @changeset_types}
    |> Ecto.Changeset.cast(params, [:current_password])
    |> User.email_changeset(params)
    |> Ecto.Changeset.validate_required(:current_password)
  end

  defp password_changeset(user, params \\ %{}) do
    user
    |> Ecto.Changeset.cast(params, [:password])
    |> User.validate_password([])
    |> User.validate_current_password(
      params |> Map.get("password_to_change"),
      :password_to_change
    )
  end

  defp name_changeset(user, params \\ %{}) do
    user
    |> User.name_changeset(params)
  end

  defp phone_changeset(user, params \\ %{}) do
    user
    |> Onboardings.user_onboarding_phone_changeset(params)
  end

  defp organization_name_changeset(%{organization: organization}, params \\ %{}) do
    organization
    |> Organization.name_changeset(params)
  end

  defp organization_address_changeset(%{organization: organization}, params \\ %{}) do
    organization
    |> Organization.address_changeset(params)
  end

  defp time_zone_changeset(user, params \\ %{}) do
    user
    |> User.time_zone_changeset(params)
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "action" => "update_email",
          "user" => user_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    changeset =
      user
      |> email_changeset(user_params)
      |> Map.put(:action, :validate)

    socket |> assign(:email_changeset, changeset) |> assign_is_save_settings() |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "action" => "update_password",
          "user" => user_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    changeset =
      user
      |> password_changeset(user_params)
      |> Map.put(:action, :validate)

    socket |> assign(:password_changeset, changeset) |> assign_is_save_settings() |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "action" => "update_organization_name",
          "organization" => organization_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    changeset =
      organization_name_changeset(user, organization_params)
      |> Map.put(:action, :validate)

    socket
    |> assign(:organization_name_changeset, changeset)
    |> assign_is_save_settings()
    |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "action" => "update_user_name",
          "user" => user_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    user
    |> name_changeset(user_params)
    |> Map.put(:action, :validate)
    |> then(&assign(socket, :name_changeset, &1))
    |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "action" => "update_organization_address",
          "organization" => organization_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    user
    |> organization_address_changeset(organization_params)
    |> Map.put(:action, :validate)
    |> then(&assign(socket, :organization_address_changeset, &1))
    |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "action" => "update_time_zone",
          "user" => user_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    changeset =
      time_zone_changeset(user, user_params)
      |> Map.put(:action, :validate)

    socket |> assign(:time_zone_changeset, changeset) |> assign_is_save_settings() |> noreply()
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "action" => "update_phone",
          "user" => phone_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    changeset =
      phone_changeset(user, phone_params)
      |> Map.put(:action, :validate)

    socket |> assign(:phone_changeset, changeset) |> assign_is_save_settings() |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        %{
          "action" => "update_email",
          "user" => %{"current_password" => password} = user_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        socket
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> assigns_email_changeset()
        |> noreply()

      {:error, changeset} ->
        socket |> assign(email_changeset: changeset) |> noreply()
    end
  end

  @impl true
  def handle_event(
        "save",
        %{
          "action" => "update_password",
          "user" => user_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    changeset =
      password_changeset(user, user_params)
      |> User.validate_current_password(
        user_params |> Map.get("password_to_change"),
        :password_to_change
      )
      |> Map.put(:action, :validate)

    socket
    |> assign(
      password_changeset: changeset,
      submit_changed_password: changeset.valid?
    )
    |> assigns_password_changeset()
    |> noreply()
  end

  @impl true
  def handle_event("save", %{"action" => "update_organization_name"}, socket) do
    socket
    |> TodoplaceWeb.ConfirmationComponent.open(%{
      close_label: "Cancel",
      confirm_event: "change-name",
      confirm_label: "Yes, change name",
      icon: "warning-orange",
      title: "Are you sure?",
      subtitle: "Changing your business name will update throughout Todoplace."
    })
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        %{"action" => "update_user_name", "user" => user_params},
        %{assigns: %{current_user: user}} = socket
      ) do
    user
    |> name_changeset(user_params)
    |> Repo.update()
    |> case do
      {:ok, user} ->
        socket
        |> put_flash(:success, "User name changed successfully")
        |> assign(current_user: user)
        |> assign(:name_changeset, name_changeset(user))

      {:error, changeset} ->
        assign(socket, name_changeset: changeset)
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        %{
          "action" => "update_organization_address",
          "organization" => organization_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    user
    |> organization_address_changeset(organization_params)
    |> Repo.update()
    |> case do
      {:ok, organization} ->
        socket
        |> put_flash(:success, "Business address changed successfully")
        |> assign(
          :organization_address_changeset,
          organization_address_changeset(%{organization: organization})
        )

      {:error, changeset} ->
        assign(socket, organization_address_changeset: changeset)
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "save",
        %{
          "action" => "update_time_zone",
          "user" => user_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    changeset = time_zone_changeset(user, user_params)

    case Repo.update(changeset) do
      {:ok, _user} ->
        socket
        |> put_flash(:success, "Timezone changed successfully")
        |> assigns_time_changeset()
        |> noreply()

      {:error, changeset} ->
        socket |> assign(time_zone_changeset: changeset) |> noreply()
    end
  end

  @impl true
  def handle_event(
        "save",
        %{
          "action" => "update_phone",
          "user" => phone_params
        },
        %{assigns: %{current_user: user}} = socket
      ) do
    case phone_changeset(user, phone_params) |> Repo.update() do
      {:ok, updated_user} ->
        socket
        |> assign(current_user: updated_user)
        |> put_flash(:success, "Phone number updated successfully")
        |> assigns_phone_changeset()
        |> noreply()

      {:error, changeset} ->
        socket |> assign(phone_changeset: changeset) |> noreply()
    end
  end

  @impl true
  def handle_event("open-billing", _params, socket) do
    {:ok, url} =
      Subscriptions.billing_portal_link(
        socket.assigns.current_user,
        url(~p"/users/settings")
      )

    socket |> redirect(external: url) |> noreply()
  end

  @impl true
  def handle_event("open-promo-code-modal", _params, %{assigns: assigns} = socket) do
    socket
    |> TodoplaceWeb.Live.User.Settings.PromoCodeModal.open(Map.take(assigns, [:current_user]))
    |> noreply()
  end

  @impl true
  def handle_event(
        "login-affiliate",
        _params,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case RewardfulAffiliate.generate_magic_link(current_user) do
      {:ok, url} ->
        socket
        |> redirect(external: url)

      {:error, error} ->
        socket |> put_flash(:error, error)
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "create-affiliate",
        _params,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    with {:ok, data} <- RewardfulAffiliate.create_affiliate(current_user),
         {:ok, user} <-
           Rewardful.changeset(current_user.rewardful_affiliate, %{
             affiliate_id: data.id,
             affiliate_token: data.token
           })
           |> Repo.update() do
      socket
      |> assign(current_user: user)
      |> put_flash(:success, "Affiliate created successfully")
    else
      {:error, error} ->
        socket
        |> put_flash(:error, error)
    end
    |> noreply()
  end

  @impl true
  def handle_event("sign_out", _params, socket) do
    socket
    |> assign(sign_out: true)
    |> noreply()
  end

  @impl true
  def handle_event("intro_js" = event, params, socket),
    do: TodoplaceWeb.LiveHelpers.handle_event(event, params, socket)

  @impl true
  def handle_event(
        "subscription-prepurchase",
        _,
        socket
      ) do
    build_invoice_link(socket)
  end

  @impl true
  def handle_event(
        "subscription-prepurchase-dismiss",
        _,
        %{assigns: %{current_user: current_user, sale_promotion_code: sale_promotion_code}} =
          socket
      ) do
    case Promotions.insert_or_update_promotion(current_user, %{
           slug: sale_promotion_code,
           name: "Holiday",
           state: :dismissed
         }) do
      {:ok, sale_promotion_code} ->
        socket
        |> assign(
          :current_sale,
          sale_promotion_code
        )
        |> put_flash(:success, "Deal hidden successfully")

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to dismiss promotion")
    end
    |> noreply()
  end

  @impl true
  def handle_event(
        "feature-flag",
        %{"flag" => flag},
        %{assigns: %{current_user: current_user}} = socket
      ) do
    flag = String.to_atom(flag)

    if FunWithFlags.enabled?(flag, for: current_user) do
      FunWithFlags.disable(flag, for_actor: current_user)
    else
      FunWithFlags.enable(flag, for_actor: current_user)
    end

    socket
    |> put_flash(:success, "Beta feature toggled")
    |> push_redirect(to: ~p"/home")
    |> noreply()
  end

  @impl true
  def handle_info(
        {:confirm_event, "change-name"},
        %{assigns: %{organization_name_changeset: changeset}} = socket
      ) do
    changeset = changeset |> Map.put(:action, nil)

    case Repo.update(changeset) do
      {:ok, _organization} ->
        socket
        |> close_modal()
        |> put_flash(:success, "Business name changed successfully")
        |> assigns_name_changeset()
        |> noreply()

      {:error, changeset} ->
        socket |> close_modal() |> assign(organization_name_changeset: changeset) |> noreply()
    end
  end

  def handle_info(
        {:close_event, %{event_name: "close_promo_code"}},
        socket
      ) do
    socket
    |> put_flash(:success, "Updated promo code")
    |> redirect(to: ~p"/users/settings")
    |> close_modal()
    |> assigns_changesets()
    |> noreply()
  end

  def settings_nav(assigns) do
    assigns = assigns |> Enum.into(%{container_class: "", intro_id: nil})

    ~H"""
    <div class="flex items-center gap-1 center-container px-6 pt-10 mt-10 sm:mt-0"><h1 class="text-4xl font-bold">Your Settings</h1></div>

    <div class={"flex flex-col flex-1 px-6 center-container #{@container_class}"} {if @intro_id, do: intro(@current_user, @intro_id), else: []}>
      <._settings_nav socket={@socket} live_action={@live_action} current_user={@current_user}>
        <:link to={"/package_templates"}>Packages</:link>
        <:link to={"/contracts"}>Contracts</:link>
        <:link to={"/questionnaires"}>Questionnaires</:link>
        <:link to={"/calendar/settings"}>Calendar</:link>
        <:link to={"/galleries/settings"}>Gallery</:link>
        <:link to={"/finance"}>Payments</:link>
        <:link to={"/brand"}>Brand</:link>
        <:link hide={!show_pricing_tab?()} to={"/pricing"}>Gallery Store Pricing</:link>
        <:link to={"/profile/settings"}>Public Profile</:link>
        <:link to={"/users/settings"}>Account</:link>
      </._settings_nav>
      <hr />

      <%= render_slot @inner_block %>
    </div>
    """
  end

  def card(assigns) do
    assigns = Enum.into(assigns, %{class: "", id: "", title_badge: nil, select: false})

    ~H"""
    <div class={"mb-5 flex overflow-hidden border rounded-lg #{@class}"} id={@id}>
      <div class="w-4 border-r bg-blue-planning-300" />

      <div class={classes("flex flex-col justify-between w-full p-10", %{"pl-14 -ml-4" => @select})}>

        <div class="flex flex-col items-start sm:items-center sm:flex-row">
          <h1 class="mb-2 mr-4 text-xl font-bold sm:text-2xl text-blue-planning-300"><%= @title %></h1>
          <%= if @title_badge do %>
            <.badge color={:gray}><%= @title_badge %></.badge>
          <% end %>
        </div>

        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  defp sign_out(assigns) do
    ~H"""
      <.form class={@class} :let={_} for={%{}} as={:sign_out} action={~p"/users/log_out"} method="delete" phx-trigger-action={@sign_out} phx-submit="sign_out">
        <%= submit "Sign out", class: "btn-primary w-full" %>
      </.form>
    """
  end

  defp _settings_nav(assigns) do
    ~H"""
    <ul class="flex py-4 overflow-auto font-bold text-blue-planning-300" {testid("settings-nav")}>
    <%= for %{to: to} = link <- @link, !Map.get(link, :hide) do %>
        <li>
           <.nav_link title={to} :let={active} to={to} class="block whitespace-nowrap border-b-4 border-transparent transition-all duration-300 hover:border-b-blue-planning-300" active_class="border-b-blue-planning-300" socket={@socket} live_action={@live_action}>
            <div {if active, do: %{id: "active-settings-nav-link", phx_hook: "ScrollIntoView"}, else: %{}} class="px-3 py-2">
              <%= render_slot(link) %>
            </div>
          </.nav_link>
        </li>
      <% end %>
    </ul>
    """
  end

  defp show_pricing_tab?,
    do: Enum.member?(Application.get_env(:todoplace, :feature_flags, []), :show_pricing_tab)

  def time_zone_options() do
    TzExtra.countries_time_zones()
    |> Enum.sort_by(&{&1.utc_offset, &1.time_zone})
    |> Enum.map(&{"(GMT#{&1.pretty_utc_offset}) #{&1.time_zone}", &1.time_zone})
    |> Enum.uniq()
  end

  def subscription_badge(%Subscription{} = subscription) do
    days_left =
      ngettext(
        "1 day",
        "%{count} days",
        days_distance(subscription.current_period_end) |> Kernel.max(0)
      )

    cond do
      subscription.cancel_at != nil ->
        "#{days_left} left until your subscription ends"

      subscription.status == "trialing" ->
        "#{days_left} left in your trial"

      true ->
        nil
    end
  end

  defp build_invoice_link(
         %{
           assigns: %{
             current_user: current_user,
             sale_promotion_code: sale_promotion_code
           }
         } = socket
       ) do
    discounts_data =
      if sale_promotion_code,
        do: %{
          discounts: [
            %{
              coupon: Subscriptions.maybe_return_promotion_code_id?(sale_promotion_code)
            }
          ]
        },
        else: %{}

    stripe_params =
      %{
        client_reference_id: "blackfriday_2023",
        cancel_url: url(~p"/users/settings"),
        success_url:
          "#{url(~p"/users/settings?pre_purchase=true&checkout_session_id={CHECKOUT_SESSION_ID}")}",
        billing_address_collection: "auto",
        customer: Subscriptions.user_customer_id(current_user),
        line_items: [
          %{
            price_data: %{
              currency: "USD",
              unit_amount: 35_000,
              product_data: %{
                name: "Holiday 2023",
                description: "Pre purchase your next year of Todoplace!"
              },
              tax_behavior: "exclusive"
            },
            quantity: 1
          }
        ]
      }
      |> Map.merge(discounts_data)

    case Payments.create_session(stripe_params, []) do
      {:ok, %{url: url}} ->
        socket |> redirect(external: url) |> noreply()

      {:error, error} ->
        Logger.warning("Error redirecting to Stripe: #{inspect(error)}")
        socket |> put_flash(:error, "Couldn't redirect to Stripe. Please try again") |> noreply()
    end
  end

  defp assign_preferred_phone_country(
         %{assigns: %{current_user: %{onboarding: %{country: "US"}}}} = socket
       ) do
    assign(socket, :preferred_phone_country, default_preferred_phone_country())
  end

  defp assign_preferred_phone_country(
         %{assigns: %{current_user: %{onboarding: %{country: "CA"}}}} = socket
       ) do
    assign(
      socket,
      :preferred_phone_country,
      Enum.reverse(default_preferred_phone_country())
    )
  end

  defp assign_preferred_phone_country(
         %{assigns: %{current_user: %{onboarding: %{country: country}}}} = socket
       ) do
    if is_nil(country) do
      assign(socket, :preferred_phone_country, default_preferred_phone_country())
    else
      assign(socket, :preferred_phone_country, [country] ++ default_preferred_phone_country())
    end
  end

  defp assign_preferred_phone_country(socket) do
    assign(socket, :preferred_phone_country, default_preferred_phone_country())
  end

  defp default_preferred_phone_country(), do: ["US", "CA"]

  defp user_has_affiliate_link?(%{rewardful_affiliate: affiliate}) do
    case affiliate do
      %Ecto.Association.NotLoaded{} -> false
      nil -> false
      _ -> affiliate.affiliate_id != nil and affiliate.affiliate_token != nil
    end
  end
end
