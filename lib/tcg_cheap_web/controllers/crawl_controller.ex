defmodule TcgCheapWeb.CrawlController do
  use TcgCheapWeb, :controller

  alias TcgCheap.Sealed

  def sitemap(conn, _params) do
    products = Sealed.list_products!(query: [select: [:slug], sort: [:slug]])

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
