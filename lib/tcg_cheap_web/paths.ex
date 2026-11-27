defmodule TcgCheapWeb.Paths do
  @moduledoc """
  The guide's public paths. Each region has its own path segments in its
  language (`/pl/produkty/…`, `/hu/termekek/…`, `TcgCheap.Country.region/0`)
  under the same product, set and card slugs; the articles and the bot page
  exist only in the regions that list them (`pages`), Poland so far.

  Poland's home page is the root (`/`), the page visitors from countries
  without a region of their own get too; its other pages keep the `/pl`
  prefix.

  A page is named by `parse/1` and built by `page_path/2`, which give the same
  page in another region (`switch/2`). The one-argument helpers build in the
  current region (`TcgCheapWeb.Region.current/0`). The router declares the
  same paths from the same regions.
  """

  use TcgCheapWeb, :verified_routes

  alias TcgCheapWeb.Region

  @type page ::
          :home
          | :products
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
  # The home page ends with a slash, like the region's directory.
  def page_path(%Region{code: code} = region, :home),
    do: if(Region.poland?(region), do: "/", else: "/" <> code <> "/")

  def page_path(%Region{} = region, :products), do: join(region, [region.slugs.products])
  def page_path(%Region{} = region, :cards), do: join(region, [region.slugs.cards])

  def page_path(%Region{} = region, {:product, slug}),
    do: join(region, [region.slugs.products, slug])

  def page_path(%Region{} = region, {:expansion, slug}),
    do: join(region, [region.slugs.expansions, slug])

  def page_path(%Region{slugs: slugs} = region, {:card, set, card}),
    do: join(region, [slugs.expansions, set, slugs.cards, card])

  def page_path(%Region{pages: pages} = region, page) when is_atom(page) do
    case pages do
      %{^page => slug} -> join(region, [slug])
      %{} -> nil
    end
  end

  # Each segment encoded as a verified route encodes an interpolated one.
  defp join(%Region{code: code}, segments),
    do: "/" <> Enum.map_join([code | segments], "/", &encode/1)

  defp encode(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  @doc "The region and page of a guide path, :error for any other path."
  @spec parse(String.t()) :: {:ok, Region.t(), page()} | :error
  def parse("/"), do: {:ok, Region.poland(), :home}

  def parse(path) do
    with [code | segments] <- String.split(path, "/", trim: true),
         {:ok, region} <- Region.fetch(code),
         {:ok, page} <- parse_page(region, segments) do
      {:ok, region, page}
    else
      _other -> :error
    end
  end

  defp parse_page(_region, []), do: {:ok, :home}

  defp parse_page(%Region{slugs: slugs, pages: pages}, segments) do
    %{products: products, expansions: expansions, cards: cards} = slugs

    case segments do
      [^products] ->
        {:ok, :products}

      [^cards] ->
        {:ok, :cards}

      [^products, slug] ->
        {:ok, {:product, slug}}

      [^expansions, slug] ->
        {:ok, {:expansion, slug}}

      [^expansions, set, ^cards, card] ->
        {:ok, {:card, set, card}}

      [slug] ->
        Enum.find_value(pages, :error, fn
          {page, ^slug} -> {:ok, page}
          _other -> nil
        end)

      _other ->
        :error
    end
  end

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
  A path the domain gives in the Polish form without a region prefix
  (`/rozszerzenia/<set>/karty/<card>`, `/produkty/<slug>`), in the given
  region (by default the current one).
  """
  @spec localize(Region.t(), String.t()) :: String.t()
  def localize(region \\ Region.current(), "/" <> _rest = path) do
    {:ok, _region, page} = parse("/pl" <> path)
    page_path(region, page)
  end

  @spec home() :: String.t()
  def home, do: page_path(Region.current(), :home)

  @doc "The home page with its search (`q`)."
  @spec home(Enumerable.t()) :: String.t()
  def home(params), do: with_query(home(), params)

  @doc "The products list, the cards list's equal."
  @spec products() :: String.t()
  def products, do: page_path(Region.current(), :products)

  @doc "The products list with a query, as its filters write it."
  @spec products(Enumerable.t()) :: String.t()
  def products(params), do: with_query(products(), params)

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

  @doc """
  The Cardmarket expansion id a set page's slug ends in (`"obsidian-flames-5234"`),
  or `:error` for a slug without one.
  """
  @spec expansion_id(String.t()) :: {:ok, pos_integer()} | :error
  def expansion_id(slug) do
    case Regex.run(~r/-(\d+)\z/, slug) do
      [_, id] -> expansion_id_param(id)
      nil -> :error
    end
  end

  @doc "An expansion id written as a bare number, as the list's `rozszerzenie` filter has it."
  @spec expansion_id_param(String.t()) :: {:ok, pos_integer()} | :error
  def expansion_id_param(value) do
    case Integer.parse(value) do
      {id, ""} when id in 1..9_999_999 -> {:ok, id}
      _ -> :error
    end
  end

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
