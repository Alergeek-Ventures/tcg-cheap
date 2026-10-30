defmodule TcgCheap.Catalogue.ExternalUrl do
  @moduledoc "Validation for externally supplied HTTPS URLs."

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
