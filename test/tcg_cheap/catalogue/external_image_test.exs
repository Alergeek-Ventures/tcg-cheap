defmodule TcgCheap.Catalogue.ExternalImageTest do
  use TcgCheap.DataCase, async: false

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Repo

  test "accepts every exact official image host" do
    for host <- ["assets.tcgdex.net", "assets.pokemon.com", "www.pokemon.com", "mcdn.pokemon.com"] do
      assert ExternalImage.valid?("https://#{host}/image.webp")
      assert ExternalImage.valid?("https://#{host}:443/image.webp")
    end
  end

  test "accepts retailer roots and proper subdomains" do
    for root <- [
          "lootquest.pl",
          "cardzhouse.pl",
          "boosterpoint.pl",
          "pokebooster.pl",
          "boosterland.pl",
          "colligere.pl"
        ] do
      assert ExternalImage.valid?("https://#{root}/wp-content/image.webp", [root])
      assert ExternalImage.valid?("https://cdn.images.#{root}/image.webp", [root])
    end
  end

  test "rejects unrelated and deceptive suffix hosts" do
    for host <- [
          "example.com",
          "evilcardzhouse.pl",
          "cardzhouse.pl.evil.example",
          "notlootquest.pl",
          "assets.tcgdex.net.evil.example",
          "mcdn.pokemon.com.evil.example"
        ] do
      refute ExternalImage.valid?("https://#{host}/image.webp")
    end
  end

  test "rejects retailer pseudo-subdomains with non-PostgreSQL labels" do
    refute ExternalImage.valid?("https://bad_host.lootquest.pl/image.webp", ["lootquest.pl"])
  end

  test "rejects credentials, non-HTTPS URLs, whitespace and control characters" do
    for url <- [
          "https://user:pass@assets.pokemon.com/image.webp",
          "http://assets.pokemon.com/image.webp",
          "https://assets.pokemon.com/image with-space.webp",
          "https://assets.pokemon.com/image\u0000.webp",
          "https://assets.pokemon.com/image\n.webp"
        ] do
      refute ExternalImage.valid?(url)
    end
  end

  test "rejects non-default HTTPS ports" do
    refute ExternalImage.valid?("https://assets.pokemon.com:444/image.webp")
    refute ExternalImage.valid?("https://assets.pokemon.com:bad/path")
    refute ExternalImage.valid?("https://cdn.lootquest.pl:8443/image.webp", ["lootquest.pl"])
  end

  test "the database pattern has the same default-port and rejection policy" do
    matches? = fn url ->
      [[matches]] =
        Repo.query!("SELECT $1 ~* $2", [url, ExternalImage.postgres_allowlisted_url_pattern()]).rows

      matches
    end

    for url <- [
          "https://assets.pokemon.com/image.webp",
          "https://assets.pokemon.com:443/image.webp",
          "https://cdn.boosterland.pl/image.webp",
          "https://images.colligere.pl/image.webp"
        ] do
      assert matches?.(url)
    end

    for url <- [
          "https://assets.pokemon.com:444/image.webp",
          "https://user:pass@assets.pokemon.com/image.webp",
          "https://assets.pokemon.com.evil.example/image.webp",
          "https://bad_host.lootquest.pl/image.webp",
          "https://assets.pokemon.com:bad/path",
          "https://assets.pokemon.com/image with-space.webp",
          "https://assets.pokemon.com/image\u0001.webp"
        ] do
      refute matches?.(url)
    end
  end

  test "preserves implicit HTTPS port" do
    assert ExternalImage.valid?("https://assets.pokemon.com/image.webp")
    assert ExternalImage.valid?("https://cdn.lootquest.pl/image.webp", ["lootquest.pl"])
  end
end
