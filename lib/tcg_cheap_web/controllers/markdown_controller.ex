defmodule TcgCheapWeb.MarkdownController do
  @moduledoc """
  Markdown versions of the guide's pages (`TcgCheapWeb.PageMarkdown`), routed
  here by `TcgCheapWeb.MarkdownNegotiation`. They are alternates of the HTML
  pages: kept out of the index and pointing to the HTML as canonical. Always
  in Polish, the guide's default language.
  """

  use TcgCheapWeb, :controller

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{BoosterGuide, CardGuide, CardValue, Catalogue, ExpensiveCards, Guide}
  alias TcgCheapWeb.{CardRecords, PageMarkdown, SEO}

  # The home page's default list: English editions, as the HTML opens with.
  def home(conn, _params) do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)
    {summaries, _more?, _count} = Guide.browse(list_filters(nil, :en), 0, now)
    retail_deal = List.first(Sealed.list_current_retail_deals!(today))
    seo = SEO.home(%{})

    send_markdown(conn, seo, PageMarkdown.home(seo, summaries, retail_deal, today))
  end

  # The card list's first page, as the HTML opens without a search.
  def cards(conn, _params) do
    market = Guide.singles_market()
    %{available: {cards, _more?, _count}} = Guide.card_discovery()
    seo = SEO.cards(%{}, market)

    send_markdown(conn, seo, PageMarkdown.cards(seo, cards, Date.utc_today()))
  end

  def booster_prices(conn, _params) do
    page = BoosterGuide.guide()
    seo = SEO.booster_prices(page)

    send_markdown(conn, seo, PageMarkdown.booster_prices(seo, page))
  end

  # The article as its HTML opens: the records, then the unfiltered ranking's
  # first page.
  def expensive_cards(conn, _params) do
    filters = %{set: nil, stock: :all}
    overview = ExpensiveCards.overview()
    records = CardRecords.all()
    %{cards: ranking} = ExpensiveCards.ranking(filters, 0, 30)
    seo = SEO.expensive_cards(overview, records, filters)

    send_markdown(conn, seo, PageMarkdown.expensive_cards(seo, overview, records, ranking))
  end

  def card_value(conn, _params) do
    guide = CardValue.guide()
    seo = SEO.card_value(guide)

    send_markdown(conn, seo, PageMarkdown.card_value(seo, guide))
  end

  def product(conn, %{"slug" => slug}) do
    case Guide.product(slug, DateTime.utc_now()) do
      {:ok, page} ->
        seo = SEO.product(page)
        send_markdown(conn, seo, PageMarkdown.product(seo, page))

      :error ->
        not_found(conn)
    end
  end

  # As the HTML set page: every edition of the expansion's products, under
  # the expansion's current name.
  def expansion(conn, %{"slug" => slug}) do
    with [_, id] <- Regex.run(~r/-(\d+)\z/, slug),
         {id, ""} <- Integer.parse(id),
         name when is_binary(name) <- Map.get(Guide.expansion_names([id]), id) do
      if slug == Catalogue.slug(name, id) do
        now = DateTime.utc_now()
        set_page = Guide.expansion(id, name, now)
        {summaries, _more?, _count} = Guide.browse(list_filters(id, nil), 0, now)
        seo = SEO.expansion(%{}, %{id: id, name: name}, set_page)

        send_markdown(
          conn,
          seo,
          PageMarkdown.expansion(seo, DateTime.to_date(now), set_page, summaries)
        )
      else
        moved(conn, SEO.expansion_path(id, name))
      end
    else
      _not_found -> not_found(conn)
    end
  end

  def single(conn, %{"slug" => set, "card_slug" => slug}) do
    case CardGuide.find(set, slug) do
      {:ok, card, name, path} ->
        if path == "/rozszerzenia/#{set}/karty/#{slug}" do
          page = CardGuide.page(card, name, path)
          seo = SEO.single(page)
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
