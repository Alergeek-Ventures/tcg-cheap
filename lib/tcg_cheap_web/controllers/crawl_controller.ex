defmodule TcgCheapWeb.CrawlController do
  use TcgCheapWeb, :controller

  alias TcgCheap.Sealed

  # Only products a Polish shop has in stock now: the rest of the catalogue
  # has no offer to compare, so it stays reachable but isn't submitted.
  def sitemap(conn, _params) do
    ids =
      DateTime.utc_now()
      |> Sealed.current_offers()
      |> Enum.filter(&(&1.in_stock and &1.product_id != nil))
      |> Enum.map(& &1.product_id)
      |> Enum.uniq()

    products =
      Sealed.list_products!(query: [filter: [id: [in: ids]], select: [:slug], sort: [:slug]])

    entries =
      for location <- [url(~p"/") | Enum.map(products, &url(~p"/produkty/#{&1.slug}"))] do
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
