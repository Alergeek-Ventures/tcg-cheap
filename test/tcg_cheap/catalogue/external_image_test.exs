defmodule TcgCheap.Catalogue.ExternalImageTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed.Shops

  test "accepts every exact official and shop image host" do
    for host <-
          ["assets.tcgdex.net", "assets.pokemon.com", "www.pokemon.com", "mcdn.pokemon.com"] ++
            Shops.hosts() do
      assert ExternalImage.valid?("https://#{host}/image.webp")
      assert ExternalImage.valid?("https://#{host}:443/image.webp")
    end
  end

  test "rejects unrelated, deceptive and subdomain hosts" do
    for host <- [
          "example.com",
          "evilcardzhouse.pl",
          "cardzhouse.pl.evil.example",
          "cdn.lootquest.pl",
          "assets.tcgdex.net.evil.example",
          "mcdn.pokemon.com.evil.example"
        ] do
      refute ExternalImage.valid?("https://#{host}/image.webp")
    end
  end

  test "rejects credentials, non-HTTPS URLs, other ports, whitespace and control characters" do
    for url <- [
          "https://user:pass@assets.pokemon.com/image.webp",
          "http://assets.pokemon.com/image.webp",
          "https://assets.pokemon.com:444/image.webp",
          "https://assets.pokemon.com:bad/path",
          "https://assets.pokemon.com/image with-space.webp",
          "https://assets.pokemon.com/image\u0000.webp",
          "https://assets.pokemon.com/image\n.webp",
          nil
        ] do
      refute ExternalImage.valid?(url)
    end
  end

  test "CSP sources list exactly the allowed hosts" do
    sources = ExternalImage.csp_sources()
    assert "https://colligere.pl" in sources
    assert "https://www.pokemon.com" in sources
    refute Enum.any?(sources, &String.contains?(&1, "*"))
  end
end
