defmodule TcgCheapWeb.MarkdownController do
  @moduledoc """
  Markdown versions of the guide's pages (`TcgCheapWeb.PageMarkdown`), routed
  here by `TcgCheapWeb.MarkdownNegotiation`. They are alternates of the HTML
  pages: kept out of the index and pointing to the HTML as canonical. Each
  in its region's default language (`TcgCheapWeb.Locale` puts the region).
  """

  use TcgCheapWeb, :controller

  alias TcgCheap.Cards

  alias TcgCheap.Sealed.{
    BoosterGuide,
    Catalogue,
    Deals,
    Expansions,
    ProductList,
    ProductPage,
    SetPage
  }

  alias TcgCheapWeb.{CardRecords, PageMarkdown, Paths, Region, SEO}

  # The home page: today's deals are Polish shops' and chains'.
  def home(conn, _params) do
    deals = if Region.poland?(conn.assigns.region), do: Deals.current(), else: []
    seo = SEO.Home.metadata(%{})

    send_markdown(conn, seo, PageMarkdown.home(seo, deals, Date.utc_today()))
  end

  # The products list's first page: English editions, as the HTML opens with.
  def products(conn, _params) do
    now = DateTime.utc_now()
    market = conn.assigns.region.market
    {summaries, _more?, _count} = ProductList.browse(list_filters(nil, :en), 0, now, market)
    seo = SEO.Products.metadata(%{})

    send_markdown(conn, seo, PageMarkdown.products(seo, summaries, DateTime.to_date(now)))
  end

  # The card list's first page, as the HTML opens without a search.
  def cards(conn, _params) do
    market = if Region.poland?(conn.assigns.region), do: Cards.SinglesBanner.market()
    %{available: {cards, _more?, _count}} = Cards.Guide.discovery()
    seo = SEO.Cards.metadata(%{}, market)

    send_markdown(conn, seo, PageMarkdown.cards(seo, cards, Date.utc_today()))
  end

  def booster_prices(conn, _params) do
    page = BoosterGuide.guide()
    seo = SEO.BoosterPrices.metadata(page)

    send_markdown(conn, seo, PageMarkdown.booster_prices(seo, page))
  end

  # The article as its HTML opens: the records, then the unfiltered ranking's
  # first page.
  def expensive_cards(conn, _params) do
    filters = %{set: nil, stock: :all}
    overview = Cards.Expensive.overview()
    records = CardRecords.all()
    %{cards: ranking} = Cards.Expensive.ranking(filters, 0, 30)
    seo = SEO.ExpensiveCards.metadata(overview, records, filters)

    send_markdown(conn, seo, PageMarkdown.expensive_cards(seo, overview, records, ranking))
  end

  def card_value(conn, _params) do
    guide = Cards.Value.guide()
    seo = SEO.CardValue.metadata(guide)

    send_markdown(conn, seo, PageMarkdown.card_value(seo, guide))
  end

  def product(conn, %{"slug" => slug}) do
    case ProductPage.read(slug, DateTime.utc_now(), conn.assigns.region.market) do
      {:ok, page} ->
        seo = SEO.Product.metadata(page)
        send_markdown(conn, seo, PageMarkdown.product(seo, page))

      :error ->
        not_found(conn)
    end
  end

  # As the HTML set page: every edition of the expansion's products, under
  # the expansion's current name.
  def expansion(conn, %{"slug" => slug}) do
    with {:ok, id} <- Paths.expansion_id(slug),
         name when is_binary(name) <- Map.get(Expansions.names([id]), id) do
      if slug == Catalogue.slug(name, id) do
        now = DateTime.utc_now()
        market = conn.assigns.region.market
        set_page = SetPage.read(id, name, now, market)
        {summaries, _more?, _count} = ProductList.browse(list_filters(id, nil), 0, now, market)
        seo = SEO.Expansion.metadata(%{}, %{id: id, name: name}, set_page)

        send_markdown(
          conn,
          seo,
          PageMarkdown.expansion(seo, DateTime.to_date(now), set_page, summaries)
        )
      else
        moved(conn, SEO.Expansion.path(id, name))
      end
    else
      _not_found -> not_found(conn)
    end
  end

  def single(conn, %{"slug" => set, "card_slug" => slug}) do
    case Cards.Guide.find(set, slug) do
      {:ok, card, name, path} ->
        path = Paths.localize(path)

        if path == Paths.page_path(conn.assigns.region, {:card, set, slug}) do
          page = Cards.Guide.page(card, name, path)
          seo = SEO.Single.metadata(page)
          send_markdown(conn, seo, PageMarkdown.single(seo, page))
        else
          moved(conn, path)
        end

      :error ->
        not_found(conn)
    end
  end

  defp list_filters(expansion, edition),
    do: %{query: "", kind: nil, edition: edition, expansion: expansion}

  defp send_markdown(conn, seo, body) do
    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("x-robots-tag", "noindex, follow")
    |> put_resp_header("link", ~s(<#{seo.canonical}>; rel="canonical"))
    |> send_resp(200, body)
  end

  # A renamed expansion or card moves to its current name's markdown version.
  defp moved(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: PageMarkdown.url_for(path))
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("x-robots-tag", "noindex")
    |> send_resp(404, PageMarkdown.not_found())
  end
end
