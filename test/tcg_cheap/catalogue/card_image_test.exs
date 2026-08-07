defmodule TcgCheap.Catalogue.CardImageTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.CardImage

  describe "detail_url/1" do
    test "normalizes base and qualified card URLs to high WebP" do
      for url <- [
            "https://assets.tcgdex.net/en/swsh3/136",
            "https://assets.tcgdex.net/en/swsh3/136/high.png",
            "https://assets.tcgdex.net/en/swsh3/136/high.jpg",
            "https://assets.tcgdex.net/en/swsh3/136/high.webp",
            "https://assets.tcgdex.net/en/swsh3/136/low.png",
            "https://assets.tcgdex.net/en/swsh3/136/low.jpg",
            "https://assets.tcgdex.net/en/swsh3/136/low.webp"
          ] do
        assert CardImage.detail_url(url) == "https://assets.tcgdex.net/en/swsh3/136/high.webp"
      end
    end
  end

  describe "thumbnail_url/1" do
    test "normalizes base and qualified card URLs to low WebP" do
      assert CardImage.thumbnail_url("https://assets.tcgdex.net/en/swsh3/136") ==
               "https://assets.tcgdex.net/en/swsh3/136/low.webp"

      assert CardImage.thumbnail_url("https://assets.tcgdex.net/en/swsh3/136/high.jpg") ==
               "https://assets.tcgdex.net/en/swsh3/136/low.webp"
    end
  end

  test "rejects blank, non-binary, and malformed values" do
    for value <- [nil, 123, "", "   ", "https://assets.tcgdex.net", "https://assets.tcgdex.net/"] do
      assert CardImage.detail_url(value) == nil
      assert CardImage.thumbnail_url(value) == nil
    end
  end

  test "rejects non-TCGdex URLs and URL components that could alter their meaning" do
    for url <- [
          "http://assets.tcgdex.net/en/swsh3/136",
          "https://cdn.tcgdex.net/en/swsh3/136",
          "https://assets.tcgdex.net.evil.example/en/swsh3/136",
          "https://user:password@assets.tcgdex.net/en/swsh3/136",
          "https://assets.tcgdex.net:8443/en/swsh3/136",
          "https://assets.tcgdex.net/en/swsh3/136?download=1",
          "https://assets.tcgdex.net/en/swsh3/136#image"
        ] do
      assert CardImage.detail_url(url) == nil
    end
  end

  test "rejects paths that are not card image bases or documented assets" do
    for url <- [
          "https://assets.tcgdex.net//",
          "https://assets.tcgdex.net/en/swsh3/",
          "https://assets.tcgdex.net/en/swsh3/136.png",
          "https://assets.tcgdex.net/en/../swsh3/136",
          "https://assets.tcgdex.net/en/%ZZ/136",
          "https://assets.tcgdex.net/en/swsh3/136/high.gif"
        ] do
      assert CardImage.thumbnail_url(url) == nil
    end
  end
end
