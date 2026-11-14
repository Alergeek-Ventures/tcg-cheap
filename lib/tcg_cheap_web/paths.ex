defmodule TcgCheapWeb.Paths do
  @moduledoc """
  The guide's public paths. Each region has its own path segments in its
  language (`/pl/produkty/…`, `/hu/termekek/…`) under the same product, set
  and card slugs; the articles and the bot page are only Polish for now.

  A page is named by `parse/1` and built by `page_path/2`, which give the same
  page in another region (`switch/2`). The one-argument helpers build in the
  current region (`TcgCheapWeb.Region.current/0`).
  """

  use TcgCheapWeb, :verified_routes

  alias TcgCheapWeb.Region

  @type page ::
          :home
          | :cards
          | {:product, String.t()}
          | {:expansion, String.t()}
          | {:card, String.t(), String.t()}
          | :booster_prices
          | :expensive_cards
          | :card_value
          | :bot

  @doc "A page's path in a region, nil when the region does not have it."
  @spec page_path(Region.t(), page()) :: String.t() | nil
  def page_path(%Region{code: "pl"}, page), do: polish(page)
  def page_path(%Region{code: "hu"}, page), do: hungarian(page)

  # The home page ends with a slash, like the region's directory.
  defp polish(:home), do: ~p"/pl" <> "/"
  defp polish(:cards), do: ~p"/pl/karty"
  defp polish({:product, slug}), do: ~p"/pl/produkty/#{slug}"
  defp polish({:expansion, slug}), do: ~p"/pl/rozszerzenia/#{slug}"
  defp polish({:card, set, card}), do: ~p"/pl/rozszerzenia/#{set}/karty/#{card}"
  defp polish(:booster_prices), do: ~p"/pl/ile-kosztuje-booster-pokemon"
  defp polish(:expensive_cards), do: ~p"/pl/najdrozsze-karty-pokemon"
  defp polish(:card_value), do: ~p"/pl/jak-sprawdzic-wartosc-karty-pokemon"
  defp polish(:bot), do: ~p"/pl/bot"

  defp hungarian(:home), do: ~p"/hu" <> "/"
  defp hungarian(:cards), do: ~p"/hu/kartyak"
  defp hungarian({:product, slug}), do: ~p"/hu/termekek/#{slug}"
  defp hungarian({:expansion, slug}), do: ~p"/hu/szettek/#{slug}"
  defp hungarian({:card, set, card}), do: ~p"/hu/szettek/#{set}/kartyak/#{card}"
  defp hungarian(_polish_only), do: nil

  @doc "The region and page of a guide path, :error for any other path."
  @spec parse(String.t()) :: {:ok, Region.t(), page()} | :error
  def parse(path) do
    with [code | segments] <- String.split(path, "/", trim: true),
         {:ok, region} <- Region.fetch(code),
         {:ok, page} <- parse_page(code, segments) do
      {:ok, region, page}
    else
      _other -> :error
    end
  end

  defp parse_page(_code, []), do: {:ok, :home}
  defp parse_page("pl", ["karty"]), do: {:ok, :cards}
  defp parse_page("pl", ["produkty", slug]), do: {:ok, {:product, slug}}
  defp parse_page("pl", ["rozszerzenia", slug]), do: {:ok, {:expansion, slug}}
  defp parse_page("pl", ["rozszerzenia", set, "karty", card]), do: {:ok, {:card, set, card}}
  defp parse_page("pl", ["ile-kosztuje-booster-pokemon"]), do: {:ok, :booster_prices}
  defp parse_page("pl", ["najdrozsze-karty-pokemon"]), do: {:ok, :expensive_cards}
  defp parse_page("pl", ["jak-sprawdzic-wartosc-karty-pokemon"]), do: {:ok, :card_value}
  defp parse_page("pl", ["bot"]), do: {:ok, :bot}
  defp parse_page("hu", ["kartyak"]), do: {:ok, :cards}
  defp parse_page("hu", ["termekek", slug]), do: {:ok, {:product, slug}}
  defp parse_page("hu", ["szettek", slug]), do: {:ok, {:expansion, slug}}
  defp parse_page("hu", ["szettek", set, "kartyak", card]), do: {:ok, {:card, set, card}}
  defp parse_page(_code, _segments), do: :error

  @doc """
  The same page in another region, without its query (filters are the
  region's own), or that region's home page when it has no such page.
  """
  @spec switch(String.t(), Region.t()) :: String.t()
  def switch(path, %Region{} = to) do
    case parse(path) do
      {:ok, _from, page} -> page_path(to, page) || page_path(to, :home)
      :error -> page_path(to, :home)
    end
  end

  @doc """
  A path the domain gives in the region-less Polish form it predates regions
  with (`/rozszerzenia/<set>/karty/<card>`, `/produkty/<slug>`), in the
  current region.
  """
  @spec localize(Region.t(), String.t()) :: String.t()
  def localize(region \\ Region.current(), "/" <> _rest = path) do
    {:ok, _region, page} = parse("/pl" <> path)
    page_path(region, page)
  end

  @spec home() :: String.t()
  def home, do: page_path(Region.current(), :home)

  @doc "The home page with a query, as the products list's filters write it."
  @spec home(Enumerable.t()) :: String.t()
  def home(params), do: with_query(home(), params)

  @spec cards() :: String.t()
  def cards, do: page_path(Region.current(), :cards)

  @spec cards(Enumerable.t()) :: String.t()
  def cards(params), do: with_query(cards(), params)

  @spec product(String.t()) :: String.t()
  def product(slug), do: page_path(Region.current(), {:product, slug})

  @spec expansion(String.t()) :: String.t()
  def expansion(slug), do: page_path(Region.current(), {:expansion, slug})

  @spec expansion(String.t(), Enumerable.t()) :: String.t()
  def expansion(slug, params), do: with_query(expansion(slug), params)

  @doc "An article's or the bot page's path in the current region, nil where it has none."
  @spec page(page()) :: String.t() | nil
  def page(page), do: page_path(Region.current(), page)

  @doc "A path's full URL on the site."
  @spec url(String.t()) :: String.t()
  def url(path), do: unverified_url(TcgCheapWeb.Endpoint, path)

  defp with_query(path, params) do
    case URI.encode_query(params) do
      "" -> path
      query -> path <> "?" <> query
    end
  end
end
