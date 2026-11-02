defmodule TcgCheap.Catalogue.ExternalImage do
  @moduledoc """
  The allowlist for background downloads of card and product images: the official
  Pokémon and TCGdex image hosts, the REBEL wholesaler's and other retailers'
  pictures of what sealed products hold, plus the image hosts of the
  buying-guide shops. Browsers only
  render local assets and our own storage.
  """

  alias TcgCheap.Catalogue.ExternalUrl
  alias TcgCheap.Sealed.Shops

  @official_hosts [
    "assets.tcgdex.net",
    "assets.pokemon.com",
    "www.pokemon.com",
    "mcdn.pokemon.com",
    "files.rebel.pl"
  ]

  # Retailers and news sites whose public pictures of what a sealed product
  # holds were checked by eye and set as contents item photos.
  @contents_photo_hosts [
    "card-binder.com",
    "cdn11.bigcommerce.com",
    "d1avvq5q4v8v8k.cloudfront.net",
    "media3.nin-nin-game.com",
    "pokemonplug.com",
    "primary.jwwb.nl",
    "quazacollect.com",
    "remicardtrader.ca",
    "tbcgames.com",
    "tools.toywiz.com",
    "www.asmodee.co.uk",
    "www.pokebox.com.au",
    "www.stompinggroundstcg.com",
    "zenpan-japan.com"
  ]

  @doc "Every host an image may be rendered from."
  @spec hosts() :: [String.t()]
  def hosts, do: @official_hosts ++ @contents_photo_hosts ++ Shops.image_hosts()

  @doc "Returns the CSP image sources: local assets and our own object storage only."
  @spec csp_sources() :: [String.t()]
  def csp_sources,
    do: ["'self'", "data:", TcgCheap.Storage.public_origin()]

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
