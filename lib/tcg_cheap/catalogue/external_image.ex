defmodule TcgCheap.Catalogue.ExternalImage do
  @moduledoc "The allowlist for externally rendered product and listing images.

  `postgres_allowlisted_url_check/1` is deliberately kept in this module so the
  database constraints and the application validator use the same host policy.
  "

  alias TcgCheap.Catalogue.ExternalUrl

  @official_hosts [
    "assets.tcgdex.net",
    "assets.pokemon.com",
    "www.pokemon.com",
    "mcdn.pokemon.com"
  ]
  @retailer_roots [
    "lootquest.pl",
    "cardzhouse.pl",
    "boosterpoint.pl",
    "pokebooster.pl",
    "boosterland.pl",
    "colligere.pl"
  ]
  @official_host_pattern Enum.map_join(@official_hosts, "|", &Regex.escape/1)
  @retailer_root_pattern Enum.map_join(@retailer_roots, "|", &Regex.escape/1)
  @postgres_allowlisted_url_pattern "^https://((#{@official_host_pattern})|([a-z0-9-]+\\.)*(#{@retailer_root_pattern}))(:443)?(/|[/?#][^[:space:][:cntrl:]]*)?$"

  @doc "Returns the exact PostgreSQL-compatible URL pattern used by this policy."
  @spec postgres_allowlisted_url_pattern() :: String.t()
  def postgres_allowlisted_url_pattern, do: @postgres_allowlisted_url_pattern

  @doc "Returns a PostgreSQL-safe CHECK expression for an image URL column."
  @spec postgres_allowlisted_url_check(String.t()) :: String.t()
  def postgres_allowlisted_url_check(column),
    do: "#{column} ~* '#{@postgres_allowlisted_url_pattern}'"

  @doc "Returns the CSP image sources represented by this policy."
  @spec csp_sources() :: [String.t()]
  def csp_sources do
    ["'self'", "data:"] ++
      Enum.flat_map(@official_hosts, &["https://#{&1}"]) ++
      Enum.flat_map(@retailer_roots, &["https://#{&1}", "https://*.#{&1}"])
  end

  @spec valid?(term(), term()) :: boolean()
  def valid?(url, retailer_roots \\ @retailer_roots) do
    with true <- ExternalUrl.valid?(url),
         %URI{host: host, port: port} <- URI.parse(url),
         true <- is_binary(host),
         true <- port in [nil, 443],
         true <- allowed_host?(String.downcase(host), retailer_roots),
         true <- Regex.match?(~r/^https:\/\/[^\s]+$/i, url) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp allowed_host?(host, retailer_roots) do
    host in @official_hosts or
      Enum.any?(List.wrap(retailer_roots), fn root -> proper_subdomain?(host, root) end)
  end

  defp proper_subdomain?(host, root) when is_binary(root) do
    root = root |> String.downcase() |> String.trim_leading(".")

    root in @retailer_roots and
      Regex.match?(~r/^([a-z0-9-]+\.)*[a-z0-9-]+$/, host) and
      (host == root or String.ends_with?(host, "." <> root))
  end

  defp proper_subdomain?(_, _), do: false
end
