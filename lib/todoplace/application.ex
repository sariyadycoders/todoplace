defmodule Todoplace.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    System.cmd("redis-cli", ["FLUSHALL"])
    topologies = Application.get_env(:todoplace, :topologies) || []
    producer_module = Application.get_env(:todoplace, :photo_output_subscription)

    children = [
      TodoplaceWeb.Telemetry,
      Todoplace.Repo,
      {Redix,
       name: :redix,
       host: System.get_env("REDIS_HOST") || "127.0.01",
       port: String.to_integer(System.get_env("REDIS_PORT") || "6379")},
      {DNSCluster, query: Application.get_env(:todoplace, :dns_cluster_query) || :ignore},
      {Cluster.Supervisor, [topologies, [name: Todoplace.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Todoplace.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Todoplace.Finch},
      Todoplace.WHCC.Client.TokenStore,
      Todoplace.WHCC.WebhookKeeper,
      # Start a worker by calling: Todoplace.Worker.start_link(arg)
      # {Todoplace.Worker, arg},
      # Start to serve requests, typically the last entry
      TodoplaceWeb.Endpoint,
      {Task.Supervisor, name: ProjectSetup.TaskSupervisor},
      {ConCache, [name: :cache, ttl_check_interval: false]},
      {Oban, Application.fetch_env!(:todoplace, Oban)},
      # Gallery workers
      Todoplace.Galleries.Workers.PositionNormalizer,
      {Todoplace.Galleries.PhotoProcessing.ProcessedConsumer, [producer_module: producer_module]},
      Todoplace.Galleries.PhotoProcessing.Waiter,
      Todoplace.EmailAutomation.GarbageEmailCollector
    ]

    events = [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]]

    :telemetry.attach_many("oban-logger", events, &Todoplace.ObanLogger.handle_event/4, [])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Todoplace.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TodoplaceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
