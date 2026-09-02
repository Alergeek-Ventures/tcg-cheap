defmodule TcgCheap.Catalogue.ExternalUrl do
  @moduledoc "Validation for externally supplied HTTPS URLs."

  @postgres_url_pattern "^https://[^/:@?#[:space:][:cntrl:]]+(:[0-9]+)?(/|[/?#][^[:space:][:cntrl:]]*)?$"

  @doc "Returns the PostgreSQL-compatible pattern for safe external HTTPS URLs."
  @spec postgres_url_pattern() :: String.t()
  def postgres_url_pattern, do: @postgres_url_pattern

  @doc "Returns a PostgreSQL-safe CHECK expression for an external URL column."
  @spec postgres_url_check(String.t()) :: String.t()
  def postgres_url_check(column), do: "#{column} ~* '#{@postgres_url_pattern}'"

  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value) do
    value != "" and
      Regex.match?(~r/^https:\/\/[^\/:@?#\s\p{Cc}]+(:[0-9]+)?(\/|[\/?#][^\s\p{Cc}]*)?$/iu, value) and
      case URI.parse(value) do
        %URI{scheme: scheme, host: host, userinfo: nil, port: port}
        when scheme in ["https", "HTTPS"] and is_binary(host) and host != "" ->
          is_nil(port) or is_integer(port)

        _ ->
          false
      end
  rescue
    _ -> false
  end

  def valid?(_), do: false
end
