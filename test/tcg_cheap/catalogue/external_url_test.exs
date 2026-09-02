defmodule TcgCheap.Catalogue.ExternalUrlTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Catalogue.ExternalUrl

  test "accepts structurally valid HTTPS URLs" do
    for url <- [
          "https://example.com",
          "https://example.com:443/path?query=value#fragment",
          "https://example.com/?query=value",
          "https://example.com/#fragment"
        ] do
      assert ExternalUrl.valid?(url)
    end
  end

  test "rejects malformed HTTPS URL shapes" do
    for url <- [
          "",
          "http://example.com/path",
          "https:///path",
          "https://user:pass@example.com/path",
          "https://example.com:bad/path",
          "https://example.com/path with-space",
          "https://example.com/path\u0001"
        ] do
      refute ExternalUrl.valid?(url)
    end
  end
end
