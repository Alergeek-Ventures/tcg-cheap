defmodule TcgCheapWeb.CrawlController do
  use TcgCheapWeb, :controller

  use Gettext, backend: TcgCheapWeb.Gettext

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{CardGuide, Catalogue, Guide, Shops, Sitemap}
  alias TcgCheap.WebBotAuth
  alias TcgCheapWeb.{PageMarkdown, Paths, Polish, Region, SEO}

  # Every region's pages: each indexes its home page, card list, set and card
  # pages alike; a product page where its region's shops have it in stock now
  # (`TcgCheapWeb.SEO.product/1`), and the Polish articles.
  def sitemap(conn, _params) do
    %{expansions: expansions, products: products, cards: cards} = listed_pages()
    now = DateTime.utc_now()

    # A product page changes when its lowest price does. Card pages get no
    # date: the only daily card price we keep, the Cardmarket trend, moves a
    # little for most cards every day, and a date that is always today
    # teaches search engines to ignore the sitemap's dates altogether.
    # Another region's product pages have no date yet.
    product_dates = products |> Enum.map(& &1.id) |> Sitemap.product_dates()

    # The guides read today's prices, so they change every day; the date
    # tells search engines to look again.
    today = Date.utc_today()

    locations =
      Enum.flat_map(Region.all(), fn region ->
        products =
          if Region.poland?(region),
            do: Enum.map(products, &{&1, product_dates[&1.id]}),
            else: regional_products(region, now)

        region_locations(region, expansions, products, cards, today)
      end)

    entries =
      for {location, lastmod} <- locations do
        lastmod = lastmod && {"lastmod", [], [Date.to_iso8601(lastmod)]}
        {"url", [], [{"loc", [], [location]} | List.wrap(lastmod)]}
      end

    body =
      Saxy.encode!(
        {"urlset", [{"xmlns", "http://www.sitemaps.org/schemas/sitemap/0.9"}], entries},
        version: "1.0",
        encoding: "UTF-8"
      )

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  defp region_locations(region, expansions, products, cards, today) do
    at = &Paths.url(Paths.page_path(region, &1))

    guides =
      for page <- [:booster_prices, :expensive_cards, :card_value],
          Paths.page_path(region, page),
          do: {at.(page), today}

    [{at.(:home), nil}, {at.(:cards), nil}] ++
      guides ++
      Enum.map(expansions, fn {id, name} -> {at.({:expansion, Catalogue.slug(name, id)}), nil} end) ++
      Enum.map(products, fn {product, lastmod} -> {at.({:product, product.slug}), lastmod} end) ++
      Enum.map(cards, fn {_id, _name, path} ->
        {Paths.url(Paths.localize(region, path)), nil}
      end)
  end

  defp regional_products(region, now) do
    ids = region.market |> Guide.in_stock_ids(now) |> MapSet.to_list()

    [query: [filter: [id: [in: ids]], select: [:slug], sort: [:slug]]]
    |> Sealed.list_products!()
    |> Enum.map(&{&1, nil})
  end

  # Only products and cards a compared shop has in stock now, and their
  # expansions' set pages: the rest of the catalogue has no offer to compare,
  # so it stays reachable but isn't submitted.
  defp listed_pages do
    ids =
      DateTime.utc_now()
      |> Sealed.current_offers(:all, select: [:product_id, :in_stock])
      |> Enum.filter(
        &(&1.in_stock and &1.product_id != nil and &1.shop not in Shops.listed_only_keys())
      )
      |> Enum.map(& &1.product_id)
      |> Enum.uniq()

    products =
      Sealed.list_products!(
        query: [
          filter: [id: [in: ids]],
          select: [:slug, :cardmarket_expansion_id],
          sort: [:slug]
        ]
      )

    # Set pages under the names they are shown with: named expansions only.
    in_stock = MapSet.new(products, & &1.cardmarket_expansion_id)

    sealed_sets =
      %{query: "", kind: nil, region: nil, expansion: nil}
      |> Guide.facets()
      |> Map.fetch!(:expansions)
      |> Enum.filter(&MapSet.member?(in_stock, &1.id))
      |> Map.new(&{&1.id, &1.name})

    cards = CardGuide.sitemap_cards()

    # A set whose cards are in stock but whose sealed products are not still
    # lists those cards, under the name their paths use.
    expansions =
      cards
      |> Map.new(fn {id, name, _path} -> {id, name} end)
      |> Map.merge(sealed_sets)
      |> Enum.sort()

    %{expansions: expansions, products: products, cards: cards}
  end

  # A map of the guide for AI agents (llmstxt.org): what it is, how it rates
  # a price, and the set pages of the sitemap, newest first, as markdown.
  # Keep in sync with robots.txt and the sitemap.
  def llms(conn, _params) do
    %{expansions: expansions, products: products, cards: cards} = listed_pages()
    products = Enum.frequencies_by(products, & &1.cardmarket_expansion_id)
    cards = Enum.frequencies_by(cards, &elem(&1, 0))

    sets =
      expansions
      |> Enum.reverse()
      |> Enum.map_join("\n", fn {id, name} ->
        counts =
          [
            Map.get(products, id) && in_stock_products(Map.fetch!(products, id)),
            Map.get(cards, id) && in_stock_cards(Map.fetch!(cards, id))
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        "- #{PageMarkdown.link(name, PageMarkdown.url_for(SEO.expansion_url(id, name)))}: #{counts}"
      end)

    body = """
    # TCG Cheap

    > Niezależna porównywarka cen Pokémon TCG w sklepach wysyłających do Polski: dla każdego produktu zamkniętego (boostery, booster boxy, Elite Trainer Boxy, puszki, kolekcje) i angielskiej karty pokazuje, gdzie jest teraz najtaniej i czy to dobra cena.

    #{Enum.join(PageMarkdown.method(), " ")} Bez kont. Strona jest po polsku.

    Każda strona ma wersję markdown: dodaj `.md` do adresu (strona główna: #{PageMarkdown.url_for(Paths.url(Paths.home()))}) albo wyślij nagłówek `Accept: text/markdown`.

    ## Strony

    - [Strona główna](#{PageMarkdown.url_for(Paths.url(Paths.home()))}): produkty na stanie w sklepach z najniższą ceną i oceną
    - [Ceny kart](#{PageMarkdown.url_for(Paths.url(Paths.cards()))}): angielskie karty na stanie w sklepach z najniższą ceną i oceną
    - [Ile kosztuje booster Pokémon](#{PageMarkdown.url_for(Paths.url(Paths.page(:booster_prices)))}): poradnik zakupowy – co jest w blistrach, Booster Bundle, Elite Trainer Boxach, Booster Boxach, puszkach i kolekcjach, ile dopłacasz za dodatki ponad cenę boosterów (na przykładzie najnowszego setu) i kiedy co kupić; najtańszy booster każdego z ostatnich setów i okazje w sieciówkach
    - [Najdroższe karty Pokémon](#{PageMarkdown.url_for(Paths.url(Paths.page(:expensive_cards)))}): rekordy aukcji ze źródłami i najdroższe angielskie karty dziś z cenami w polskich sklepach
    - [Jak sprawdzić wartość karty Pokémon](#{PageMarkdown.url_for(Paths.url(Paths.page(:card_value)))}): jak znaleźć numer, wersję i stan karty, rozkład cen kart w polskich sklepach i kiedy opłaca się grading

    ## Rozszerzenia

    #{sets}

    ## Optional

    - [Sitemap](#{url(~p"/sitemap.xml")}): wszystkie strony produktów, rozszerzeń i kart z ofertą na stanie
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  defp in_stock_products(count),
    do:
      ngettext("%{number} produkt na stanie", "%{number} produkty na stanie", count,
        number: Polish.number(count)
      )

  defp in_stock_cards(count),
    do:
      ngettext("%{number} karta na stanie", "%{number} karty na stanie", count,
        number: Polish.number(count)
      )

  def robots(conn, _params) do
    body = """
    User-agent: *
    Disallow: /admin
    Disallow: /mcp
    Disallow: /health
    Disallow: /lang/
    Disallow: /region/

    Sitemap: #{url(~p"/sitemap.xml")}
    # A map of the guide for AI agents: #{url(~p"/llms.txt")}
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  # The public key our requests to shops are signed with (TcgCheap.WebBotAuth),
  # itself signed for the authority it was asked at, as the directory draft
  # requires; only on our own host, so no other site can pass it off as its own.
  def signatures_directory(conn, _params) do
    with true <- conn.host == TcgCheapWeb.Endpoint.host(),
         {:ok, body, headers} <- conn |> request_url() |> URI.parse() |> WebBotAuth.directory() do
      conn
      |> merge_resp_headers(headers)
      |> put_resp_content_type("application/http-message-signatures-directory+json", nil)
      |> send_resp(200, body)
    else
      _no_directory -> send_resp(conn, 404, "")
    end
  end
end
