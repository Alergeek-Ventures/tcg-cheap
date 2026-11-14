defmodule TcgCheapWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tcg_cheap

  # The session lives in a signed and encrypted cookie. The production build
  # sends it over HTTPS only; development serves plain HTTP. The options are
  # fixed at compile time because the LiveView socket reuses them.
  @session_options [
    store: :cookie,
    key: "_tcg_cheap_key",
    signing_salt: "LO5M3vJn",
    encryption_salt: "8W5ywsi0",
    same_site: "Lax",
    secure: Mix.env() == :prod
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, session: @session_options]],
    # Keep idle polls below the ten-second timeout seen in PageSpeed's requests.
    longpoll: [window_ms: 5_000, connect_info: [:peer_data, session: @session_options]]

  # Static files from "priv/static". Outside code reloading the digested,
  # gzipped files are served.
  plug Plug.Static,
    at: "/",
    from: :tcg_cheap,
    gzip: not code_reloading?,
    only: TcgCheapWeb.static_paths(),
    # The icons are linked by their digested names (favicon-<digest>.ico) in production.
    only_matching: ~w(favicon apple-touch-icon),
    raise_on_missing_only: code_reloading?

  if Mix.env() == :dev, do: plug(Tidewave)

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug AshPhoenix.Plug.CheckCodegenStatus
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :tcg_cheap
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  # The health check comes every few seconds; its request lines would only
  # fill the logs (and Sentry Logs).
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint], log: {__MODULE__, :log_level, []}

  # Relay compressed telemetry before parsers consume or decode its body.
  plug TcgCheapWeb.AnalyticsProxy

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug :reset_locale
  plug TcgCheapWeb.LegacyPaths
  plug TcgCheapWeb.MarkdownNegotiation
  plug TcgCheapWeb.Router

  @doc false
  def log_level(%Plug.Conn{path_info: ["health" | _]}), do: false
  # A page loads dozens of images; StoredImageController logs its failures.
  def log_level(%Plug.Conn{path_info: ["img" | _]}), do: false
  def log_level(_conn), do: :info

  # A connection's process serves its requests one after another: one must
  # not inherit the region or language the previous one rendered in. Guide
  # pages set their own (TcgCheapWeb.Locale); the rest are Polish.
  defp reset_locale(conn, _opts) do
    TcgCheapWeb.Locale.put(TcgCheapWeb.Region.poland(), "pl")
    conn
  end
end
