defmodule TcgCheapWeb.MarkdownController do
  @moduledoc """
  Markdown versions of the guide's pages (`TcgCheapWeb.PageMarkdown`), routed
  here by `TcgCheapWeb.MarkdownNegotiation`. They are alternates of the HTML
  pages: kept out of the index and pointing to the HTML as canonical. Each
  in its region's default language (`TcgCheapWeb.Locale` puts the region).
  """

  use TcgCheapWeb, :controller

  alias TcgCheap.Sealed

  alias TcgCheap.Sealed.{
    BoosterGuide,
    CardGuide,
    CardValue,
    Catalogue,
    Expansions,
    ExpensiveCards,
    ProductList,
    ProductPage,
    SetPage,
    SinglesBanner
  }

  alias TcgCheapWeb.{CardRecords, PageMarkdown, Paths, Region, SEO}

  # The home page's default list: English editions, as the HTML opens with.
  def home(conn, _params) do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)
    market = conn.assigns.region.market
    {summaries, _more?, _count} = ProductList.browse(list_filters(nil, :en), 0, now, market)

    # The retail chains' deals are Polish.
    retail_deal =
      if Region.poland?(conn.assigns.region),
        do: List.first(Sealed.list_current_retail_deals!(today))

    seo = SEO.Home.metadata(%{})

    send_markdown(conn, seo, PageMarkdown.home(seo, summaries, retail_deal, today))
  end

  # The card list's first page, as the HTML opens without a search.
  def cards(conn, _params) do
    market = if Region.poland?(conn.assigns.region), do: SinglesBanner.market()
    %{available: {cards, _more?, _count}} = CardGuide.discovery()
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
    overview = ExpensiveCards.overview()
    records = CardRecords.all()
    %{cards: ranking} = ExpensiveCards.ranking(filters, 0, 30)
    seo = SEO.ExpensiveCards.metadata(overview, records, filters)

    send_markdown(conn, seo, PageMarkdown.expensive_cards(seo, overview, records, ranking))
  end

  def card_value(conn, _params) do
    guide = CardValue.guide()
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
    case CardGuide.find(set, slug) do
      {:ok, card, name, path} ->
        path = Paths.localize(path)

        if path == Paths.page_path(conn.assigns.region, {:card, set, slug}) do
          page = CardGuide.page(card, name, path)
          seo = SEO.Single.metadata(page)
          send_markdown(conn, seo, PageMarkdown.single(seo, page))
        else
          moved(conn, path)
        end

      :error ->
        not_found(conn)
    end
  end

  defp list_filters(expansion, region),
    do: %{query: "", kind: nil, region: region, expansion: expansion}

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
