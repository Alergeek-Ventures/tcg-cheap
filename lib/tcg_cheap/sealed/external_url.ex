defmodule TcgCheap.Sealed.ExternalUrl do
  @moduledoc "Validation for externally supplied HTTPS URLs."

  @https_url ~r/^https:\/\/[^\/:@?#\s\p{Cc}]+(:[0-9]+)?(\/|[\/?#][^\s\p{Cc}]*)?$/iu

  @spec valid?(term()) :: boolean()
  def valid?(value), do: match?({:ok, _uri}, parse(value))

  @doc "Parses an externally supplied URL, accepting only a valid HTTPS URL."
  @spec parse(term()) :: {:ok, URI.t()} | :error
  def parse(value) when is_binary(value) do
    with true <- value != "" and Regex.match?(@https_url, value),
         %URI{scheme: scheme, host: host, userinfo: nil, port: port} = uri
         when scheme in ["https", "HTTPS"] and is_binary(host) and host != "" and
                (is_nil(port) or is_integer(port)) <- URI.parse(value) do
      {:ok, uri}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  def parse(_), do: :error
end
