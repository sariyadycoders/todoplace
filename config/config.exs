# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

with dotenv = "#{__DIR__}/../.env",
     {:ok, data} <- File.read(dotenv),
     do:
       for(
         "export" <> kv <- String.split(data, "\n"),
         [k, v] = String.split(kv, "=", parts: 2),
         do: k |> String.trim() |> System.put_env(v)
       )

with "" <> base64 <- System.get_env("GOOGLE_APPLICATION_CREDENTIALS_JSON_BASE64"),
     {:ok, json} <- base64 |> String.trim() |> Base.decode64() do
  config :todoplace, goth_json: json
  config :goth, json: json
else
  _ ->
    json =
      System.get_env("GOOGLE_APPLICATION_CREDENTIALS")
      |> to_string()
      |> File.read!()

    config :todoplace, goth_json: json
    config :goth, json: json
end

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :todoplace,
  ecto_repos: [Todoplace.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :todoplace, TodoplaceWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "3O2nR2CPS892vIiSWKwPap76A5gKmbL6rh5QTYaw+U1hu2bj/nbjeOG70A4sLbXB",
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: TodoplaceWeb.ErrorHTML, json: TodoplaceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Todoplace.PubSub,
  live_view: [signing_salt: "2351g+BT"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
config :money, default_currency: :USD
config :todoplace, :modal_transition_ms, 400
config :todoplace, :plug_parser_length, System.get_env("PLUG_PARSER_LENGTH") || 100_000_000
config :todoplace, :payments, Todoplace.StripePayments
config :todoplace, :nylas_calendar, Todoplace.NylasCalendar.Impl
config :todoplace, :rewardful_affiliate, Todoplace.RewardfulAffiliate.Impl
config :todoplace, :email_automation_notifier, Todoplace.Notifiers.EmailAutomationNotifier.Impl
config :todoplace, :google_site_verification, System.get_env("GOOGLE_SITE_VERIFICATION")
config :todoplace, :google_analytics_api_key, System.get_env("GOOGLE_ANALYTICS_API_KEY")
config :todoplace, :google_tag_manager_api_key, System.get_env("GOOGLE_TAG_MANAGER_API_KEY")
config :todoplace, :intercom_id, System.get_env("INTERCOM_ID")
config :todoplace, :booking_reservation_seconds, 60 * 10
config :todoplace, :card_category_id, System.get_env("CARD_CATEGORY_ID")
config :todoplace, :print_category, "h3GrtaTf5ipFicdrJ"
config :todoplace, :marketing_url, "https://www.core.com/"
config :todoplace, :support_url, "https://support.core.com/"
config :todoplace, :app_url, "https://app.core.com/"

config :todoplace, :global_watermarked_path, System.get_env("GLOBAL_WATERMARKED_PATH")

config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET"),
  publishable_key: System.get_env("STRIPE_PUBLISHABLE_KEY"),
  connect_signing_secret: System.get_env("STRIPE_CONNECT_SIGNING_SECRET"),
  app_signing_secret: System.get_env("STRIPE_APP_SIGNING_SECRET")

config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google, [default_scope: "email profile", prompt: "select_account"]}
  ]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

add_suffix = fn key ->
  [
    System.get_env(key),
    System.get_env("RENDER_EXTERNAL_URL", "") |> URI.parse() |> Map.get(:host)
  ]
  |> Enum.reject(&is_nil/1)
  |> Enum.join("--")
end

config :todoplace,
  photo_output_subscription: {
    BroadwayCloudPubSub.Producer,
    subscription: add_suffix.("PHOTO_PROCESSING_OUTPUT_SUBSCRIPTION"), on_failure: :nack
  },
  photo_processing_input_topic: System.get_env("PHOTO_PROCESSING_INPUT_TOPIC"),
  photo_processing_output_topic: add_suffix.("PHOTO_PROCESSING_OUTPUT_TOPIC"),
  photo_storage_bucket: System.get_env("PHOTO_STORAGE_BUCKET"),
  photos_max_entries: System.get_env("PHOTOS_MAX_ENTRIES") || "1500",
  photo_max_file_size: System.get_env("PHOTO_MAX_FILE_SIZE") || "104857600",
  documents_max_entries: System.get_env("DOCUMENTS_MAX_ENTRIES") || "5",
  document_max_size: System.get_env("DOCUMENT_MAX_SIZE") || "104822",
  logo_max_size: System.get_env("LOGO_MAX_SIZE") || "10485760"

config :todoplace, show_arcade_tours: true

config :todoplace, :whcc,
  adapter: Todoplace.WHCC.Client,
  url: System.get_env("WHCC_URL"),
  key: System.get_env("WHCC_KEY"),
  secret: System.get_env("WHCC_SECRET"),
  webhook_url:
    System.get_env(
      "WHCC_WEBHOOK_URL",
      case System.get_env("RENDER_EXTERNAL_URL") do
        nil -> ""
        host -> host <> "/whcc/webhook"
      end
    ),
  whcc_sync_process_count: System.get_env("WHCC_SYNC_PROCESS_COUNT") || "2"

config :todoplace, :products,
  currency: "USD",
  whcc_album_id: "2qNgr3zcSx9wvTAo9",
  whcc_wall_art_id: "tfhysKwZafFtmGqpQ",
  whcc_books_id: "B9FcAHDH5T63yvvgX",
  whcc_photo_prints_id: "BBrgfCJLkGzseCdds"

config :todoplace, Oban,
  repo: Todoplace.Repo,
  queues: [default: 10, storage: 10, campaigns: 10, user_initiated: 10]

# plugins: [
#   {Oban.Plugins.Pruner, max_age: 60 * 60},
#   {Oban.Plugins.Cron,
#    crontab: [
#      {System.get_env("EMAIL_AUTOMATION_TIME") || "*/10 * * * *",
#       Todoplace.Workers.ScheduleAutomationEmail},
#      {"0 8 * * *", Todoplace.Workers.SendGalleryExpirationReminder},
#      {"0 0 * * 0", Todoplace.Workers.SyncWHCCCatalog},
#      {"0 1 * * *", Todoplace.Workers.CleanUploader}
#      #  {"*/10 * * * *", Todoplace.Workers.SendProposalReminder},
#      #  {"*/20 * * * *", Todoplace.Workers.SendShootReminder},
#      #  {"0 * * * *", Todoplace.Workers.SendPaymentScheduleReminder},
#    ]}
# ]

config :todoplace, :packages,
  calculator: [
    sheet_id: System.get_env("PACKAGES_CALCULATOR_SHEET_ID"),
    prices: System.get_env("PACKAGES_CALCULATOR_PRICES_RANGE"),
    cost_of_living: System.get_env("PACKAGES_CALCULATOR_COST_OF_LIVING_RANGE")
  ]

config :todoplace, Todoplace.Mailer,
  adapter: Swoosh.Adapters.Local,
  marketing_template: System.get_env("SENDGRID_MARKETING_TEMPLATE"),
  marketing_unsubscribe_id:
    System.get_env("SENDGRID_MARKETING_UNSUBSCRIBE_ID") |> Integer.parse(),
  client_list_transactional: System.get_env("SENDGRID_CLIENT_LIST_TRANSACTIONAL"),
  client_list_trial_welcome: System.get_env("SENDGRID_CLIENT_LIST_TRIAL_WELCOME"),
  proofing_selection_confirmation_template:
    System.get_env("SENDGRID_PROOFING_SELECTION_CONFIMATION_TEMPLATE"),
  photographer_proofing_selection_confirmation_template:
    System.get_env("SENDGRID_PHOTOGRAPHER_PROOFING_SELECTION_CONFIMATION_TEMPLATE"),
  no_reply_email: System.get_env("SENDGRID_NO_REPLY_EMAIL")

config :todoplace, :profile_images,
  bucket: System.get_env("PUBLIC_BUCKET"),
  static_host: System.get_env("GOOGLE_PUBLIC_IMAGE_HOST")

config :todoplace, :email_presets,
  sheet_id: System.get_env("EMAIL_PRESET_SHEET_ID"),
  type_ranges: System.get_env("EMAIL_PRESET_TYPE_RANGES"),
  column_map: System.get_env("EMAIL_PRESET_COLUMN_MAP")

config :todoplace, :photo_storage_service, Todoplace.Galleries.Workers.PhotoStorage.Impl

config :todoplace, :zapier,
  new_user_webhook_url: System.get_env("ZAPIER_NEW_USER_WEBHOOK_URL"),
  gallery_order_webhook_url: System.get_env("ZAPIER_GALLERY_ORDER_WEBHOOK_URL"),
  trial_user_webhook_url: System.get_env("ZAPIER_TRIAL_USER_WEBHOOK_URL"),
  subscription_ending_user_webhook_url:
    System.get_env("ZAPIER_SUBSCRIPTION_ENDING_USER_WEBHOOK_URL")

config :pdf_generator,
  raise_on_missing_wkhtmltopdf_binary: false

config :mime, :types, %{
  "text/calendar" => ["text/calendar"],
  "application/xml" => ["xml"]
}

config :todoplace, :exchange_rates,
  url: System.get_env("EXCHANGE_RATES_API_URL"),
  access_key: System.get_env("EXCHANGE_RATES_API_KEY")

config :todoplace, :nylas, %{
  client_id: System.get_env("NYLAS_CLIENT_ID", ""),
  client_secret: System.get_env("NYLAS_CLIENT_SECRET"),
  token: System.get_env("NYLAS_TOKEN"),
  redirect_uri: "/nylas/callback",
  base_url: "https://api.nylas.com",
  base_color: "#585DF6",
  todoplace_tag: "[From Todoplace]"
}

config :todoplace, :rewardful, %{
  client_secret: System.get_env("REWARDFUL_CLIENT_SECRET"),
  campaign_id: System.get_env("REWARDFUL_CAMPAIGN_ID"),
  base_url: "https://api.getrewardful.com/v1",
  allow_stripe_customer_id: false
}

config :fun_with_flags, :cache_bust_notifications, enabled: false

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: Todoplace.Repo

config :fun_with_flags, :cache,
  enabled: true,
  # in seconds
  ttl: 900

config :phoenix_swagger, json_library: Jason

config :todoplace, :phoenix_swagger,
  swagger_files: %{
    "priv/static/swagger.json" => [
      router: TodoplaceWeb.Router,
      endpoint: TodoplaceWeb.Endpoint
    ]
  }

config :todoplace, :firebase, %{
  api_key: System.get_env("FIREBASE_API_KEY"),
  auth_domain: System.get_env("FIREBASE_AUTH_DOMAIN"),
  project_id: System.get_env("FIREBASE_PROJECT_ID"),
  storage_bucket: System.get_env("FIREBASE_STORAGE_BUCKET"),
  messaging_sender_id: System.get_env("FIREBASE_MESSAGING_SENDER_ID"),
  app_id: System.get_env("FIREBASE_APP_ID"),
  measurement_id: System.get_env("FIREBASE_MEASUREMENT_ID")
}

config :triplex,
  repo: Todoplace.Repo,
  tenant_schema: "public",
  # Prefix for tenant schemas
  prefix: "tenant_"

config :cors_plug,
  origin: ["*"],
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

config :esbuild, :version, "0.23.0"
config :tailwind, :version, "3.4.6"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
