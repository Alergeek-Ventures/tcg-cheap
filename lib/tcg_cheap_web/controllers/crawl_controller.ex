defmodule TcgCheapWeb.CrawlController do
  use TcgCheapWeb, :controller

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{CardGuide, Guide, Shops}
  alias TcgCheap.WebBotAuth
  alias TcgCheapWeb.{PageMarkdown, Polish, SEO}

  def sitemap(conn, _params) do
    %{expansions: expansions, products: products, cards: cards} = listed_pages()

    locations =
      [url(~p"/"), url(~p"/karty"), url(~p"/ile-kosztuje-booster-pokemon")] ++
        Enum.map(expansions, fn {id, name} -> SEO.expansion_url(id, name) end) ++
        Enum.map(products, &url(~p"/produkty/#{&1.slug}")) ++
        Enum.map(cards, fn {_id, _name, path} -> unverified_url(TcgCheapWeb.Endpoint, path) end)

    entries =
      for location <- locations do
        {"url", [], [{"loc", [], [location]}]}
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
            Map.get(products, id) &&
              Polish.plural(Map.fetch!(products, id), "produkt", "produkty", "produktów") <>
                " na stanie",
            Map.get(cards, id) &&
              Polish.plural(Map.fetch!(cards, id), "karta", "karty", "kart") <> " na stanie"
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        "- #{PageMarkdown.link(name, PageMarkdown.url_for(SEO.expansion_url(id, name)))}: #{counts}"
      end)

    body = """
    # TCG Cheap

    > Niezależna porównywarka cen Pokémon TCG w sklepach wysyłających do Polski: dla każdego produktu zamkniętego (boostery, booster boxy, Elite Trainer Boxy, puszki, kolekcje) i angielskiej karty pokazuje, gdzie jest teraz najtaniej i czy to dobra cena.

    #{Enum.join(PageMarkdown.method(), " ")} Bez kont. Strona jest po polsku.

    Każda strona ma wersję markdown: dodaj `.md` do adresu (strona główna: #{PageMarkdown.url_for(url(~p"/"))}) albo wyślij nagłówek `Accept: text/markdown`.

    ## Strony

    - [Strona główna](#{PageMarkdown.url_for(url(~p"/"))}): produkty na stanie w sklepach z najniższą ceną i oceną
    - [Ceny kart](#{PageMarkdown.url_for(url(~p"/karty"))}): angielskie karty na stanie w sklepach z najniższą ceną i oceną
    - [Ile kosztuje booster Pokémon](#{PageMarkdown.url_for(url(~p"/ile-kosztuje-booster-pokemon"))}): najtańszy angielski booster każdego z ostatnich setów i okazje w sieciówkach (Lidl, Rossmann, Żabka…)

    ## Rozszerzenia

    #{sets}

    ## Optional

    - [Sitemap](#{url(~p"/sitemap.xml")}): wszystkie strony produktów, rozszerzeń i kart z ofertą na stanie
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  def robots(conn, _params) do
    body = """
    User-agent: *
    Disallow: /admin
    Disallow: /mcp
    Disallow: /health
    Disallow: /lang/

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
