import Config

alias TcgCheap.Storage.Config, as: StorageConfig

# Runtime configuration, executed for every environment after compilation and
# before the system starts. Do not put compile-time configuration here.

# A release starts its web server only with PHX_SERVER=true.
if System.get_env("PHX_SERVER") do
  config :tcg_cheap, TcgCheapWeb.Endpoint, server: true
end

config :tcg_cheap, TcgCheapWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4004"))]

# Object storage per resource, with this worktree's local S3 and server ports in dev.
:tcg_cheap
|> Application.fetch_env!(:storage)
|> StorageConfig.resource_configs(%{
  "S3_PORT" => System.get_env("S3_PORT"),
  "PORT" => System.get_env("PORT")
})
|> Enum.each(fn {resource, resource_config} -> config :tcg_cheap, resource, resource_config end)

# Bearer token for the AI agent MCP endpoint at /mcp (TcgCheapWeb.McpAuth).
# Without it every MCP request is refused outside development.
mcp_api_token =
  case String.trim(System.get_env("MCP_API_TOKEN", "")) do
    "" ->
      nil

    token when byte_size(token) < 32 ->
      raise """
      environment variable MCP_API_TOKEN must contain at least 32 bytes.
      Generate one with `mix phx.gen.secret`, or remove it to disable the MCP endpoint.
      """

    token ->
      token
  end

config :tcg_cheap, TcgCheapWeb.McpAuth, token: mcp_api_token

# The Ed25519 private key that signs requests to Shopify shops
# (TcgCheap.WebBotAuth): 32 random bytes, base64url without padding, e.g.
#   elixir -e 'IO.puts(Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false))'
# Without it requests go out unsigned and no key directory is served. Set it
# only in production: requests signed with any other key still name
# tcg.cheap as their agent, whose directory does not list that key.
web_bot_auth_key =
  case String.trim(System.get_env("WEB_BOT_AUTH_KEY", "")) do
    "" ->
      nil

    encoded ->
      case Base.url_decode64(encoded, padding: false) do
        {:ok, <<key::binary-size(32)>>} ->
          key

        _invalid ->
          raise "environment variable WEB_BOT_AUTH_KEY must be 32 bytes, base64url without padding."
      end
  end

config :tcg_cheap, TcgCheap.WebBotAuth, key: web_bot_auth_key

# Error reporting. Production requires SENTRY_DSN
# or the exact token "disabled"; elsewhere an unset DSN disables Sentry. The
# release is the deployed commit (SOURCE_COMMIT from Coolify), which CI
# creates in Sentry before each deployment.
sentry_dsn =
  case {String.trim(System.get_env("SENTRY_DSN", "")), config_env()} do
    {"disabled", _env} ->
      nil

    {"", :prod} ->
      raise """
      environment variable SENTRY_DSN is missing.
      Provide the Sentry project's DSN or the exact token "disabled".
      """

    {"", _env} ->
      nil

    {dsn, _env} ->
      dsn
  end

default_sentry_environment =
  if config_env() == :prod, do: "production", else: to_string(config_env())

config :sentry,
  dsn: sentry_dsn,
  environment_name: System.get_env("SENTRY_ENVIRONMENT", default_sentry_environment),
  release: System.get_env("SENTRY_RELEASE") || System.get_env("SOURCE_COMMIT")

# The project key is public browser configuration, not a personal API key.
# Leave it unset to avoid loading PostHog (including in development).
# The host is the server-side upstream; browsers use our same-origin proxy.
config :tcg_cheap, :posthog,
  api_key: String.trim(System.get_env("POSTHOG_API_KEY", "")),
  api_host:
    System.get_env("POSTHOG_API_HOST", "https://eu.i.posthog.com")
    |> String.trim()
    |> String.trim_trailing("/")

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :tcg_cheap, TcgCheapWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets
        ~r"priv/static/.*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/tcg_cheap_web/router\.ex$"E,
        ~r"lib/tcg_cheap_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :tcg_cheap, TcgCheap.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # A short burst queues more checkouts than the pool serves at once, and
    # with the default target of 50 ms a request that waited ~100 ms for a
    # connection failed with an error. DBConnection starts dropping only when
    # no checkout of a whole `queue_interval` waited less than `queue_target`,
    # and then drops those that have waited longer than twice the target; the
    # interval is halved from its default of 2000 ms so a lasting overload is
    # noticed sooner and still shed. This helps a short pile-up; it does not
    # cure a pool that stays saturated.
    queue_target: 250,
    queue_interval: 1000,
    socket_options: maybe_ipv6

  # Signs and encrypts cookies and other secrets. Development and test use
  # fixed values from their config files; production reads it from the
  # environment.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  token_signing_secret =
    case System.get_env("ADMIN_AUTH_SIGNING_SECRET") do
      nil ->
        secret_key_base

      secret when byte_size(secret) >= 32 ->
        secret

      _secret ->
        raise """
        environment variable ADMIN_AUTH_SIGNING_SECRET must contain at least 32 bytes.
        Remove it to reuse SECRET_KEY_BASE, or provide a dedicated strong secret.
        """
    end

  host =
    case String.trim(System.get_env("PHX_HOST") || "") do
      "" -> raise "environment variable PHX_HOST is missing."
      host -> host
    end

  config :tcg_cheap, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :tcg_cheap, TcgCheapWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # IPv6 on all interfaces.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :tcg_cheap, :token_signing_secret, token_signing_secret
end
