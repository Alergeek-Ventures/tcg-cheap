defmodule TcgCheapWeb.CrawlController do
  use TcgCheapWeb, :controller

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{CardGuide, Guide}
  alias TcgCheapWeb.SEO

  # Only products a Polish shop has in stock now, and their expansions' set
  # pages: the rest of the catalogue has no offer to compare, so it stays
  # reachable but isn't submitted.
  def sitemap(conn, _params) do
    ids =
      DateTime.utc_now()
      |> Sealed.current_offers(:all, select: [:product_id, :in_stock])
      |> Enum.filter(&(&1.in_stock and &1.product_id != nil))
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

    expansions =
      %{query: "", kind: nil, region: nil, expansion: nil}
      |> Guide.facets()
      |> Map.fetch!(:expansions)
      |> Enum.filter(&MapSet.member?(in_stock, &1.id))
      |> Enum.sort_by(& &1.id)

    locations =
      [url(~p"/")] ++
        Enum.map(expansions, &SEO.expansion_url(&1.id, &1.name)) ++
        Enum.map(products, &url(~p"/produkty/#{&1.slug}")) ++
        Enum.map(
          CardGuide.sitemap_paths(),
          &unverified_url(TcgCheapWeb.Endpoint, &1)
        )

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

  def robots(conn, _params) do
    body = """
    User-agent: *
    Disallow: /admin
    Disallow: /mcp
    Disallow: /health
    Disallow: /lang/

    Sitemap: #{url(~p"/sitemap.xml")}
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
