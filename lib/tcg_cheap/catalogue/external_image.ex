defmodule TcgCheap.Catalogue.ExternalImage do
  @moduledoc """
  The allowlist for externally rendered card and product images: the official
  Pokémon and TCGdex image hosts plus the image hosts of the buying-guide
  shops. The CSP image sources are derived from the same list.
  """

  alias TcgCheap.Catalogue.ExternalUrl
  alias TcgCheap.Sealed.Shops

  @official_hosts [
    "assets.tcgdex.net",
    "assets.pokemon.com",
    "www.pokemon.com",
    "mcdn.pokemon.com"
  ]

  @doc "Every host an image may be rendered from."
  @spec hosts() :: [String.t()]
  def hosts, do: @official_hosts ++ Shops.image_hosts()

  @doc "Returns the CSP image sources: this policy plus our own object storage."
  @spec csp_sources() :: [String.t()]
  def csp_sources,
    do:
      ["'self'", "data:", TcgCheap.Storage.public_origin()] ++
        Enum.map(hosts(), &"https://#{&1}")

  @spec valid?(term()) :: boolean()
  def valid?(url) do
    with true <- ExternalUrl.valid?(url),
         %URI{host: host, port: 443} when is_binary(host) <- URI.parse(url) do
      String.downcase(host) in hosts()
    else
      _ -> false
    end
  rescue
    _ -> false
  end
end
