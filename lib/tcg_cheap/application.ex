defmodule TcgCheap.Application do
  @moduledoc false

  use Application

  alias TcgCheap.Sealed.FetchWorker

  @impl true
  def start(_type, _args) do
    # Before anything can crash with a visitor's location in its state.
    :ok = TcgCheapWeb.LocationLogFilter.install()
    FetchWorker.attach_failure_reports()

    children = [
      TcgCheapWeb.Telemetry,
      TcgCheap.Repo,
      # Migrates before anything uses the database; a failing migration stops
      # the start, so a new container never becomes healthy on a bad schema.
      {Ecto.Migrator, repos: Application.fetch_env!(:tcg_cheap, :ecto_repos)},
      {AshAuthentication.Supervisor, otp_app: :tcg_cheap},
      {TcgCheapWeb.AdminLoginLimiter, Application.get_env(:tcg_cheap, :admin_login_limiter, [])},
      {DNSCluster, query: Application.get_env(:tcg_cheap, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TcgCheap.PubSub},
      {Task.Supervisor, name: TcgCheap.Storage.DownloadSupervisor},
      {Oban, Application.fetch_env!(:tcg_cheap, Oban)},
      # Start to serve requests, typically the last entry
      TcgCheapWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TcgCheap.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Keeps the endpoint configuration in step with application upgrades.
  @impl true
  def config_change(changed, _new, removed) do
    TcgCheapWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
