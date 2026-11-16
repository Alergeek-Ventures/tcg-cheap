defmodule TcgCheapWeb.SocialImageController do
  @moduledoc """
  Link-preview cards for the buying guide (see `TcgCheapWeb.SocialImage`).

  A card is rendered once per version of what it shows and kept in the
  public bucket (`social/…`); later requests are redirected there. The
  version is computed here from the current data, so the `v` parameter
  (which `TcgCheapWeb.SEO` puts in the URL for platforms that cache by URL)
  cannot force a new render. Crawlers send no session: cards are in the
  region's language and currency (`TcgCheapWeb.Locale` puts them); the Polish
  region's keys carry no region prefix.
  """

  use TcgCheapWeb, :controller

  alias AshStorage.Service.Context
  alias TcgCheap.Cards

  alias TcgCheap.Sealed.{BoosterGuide, Catalogue, Expansions, ProductPage, SetPage}

  alias TcgCheapWeb.{Paths, SocialImage}

  require Logger

  def home(conn, _params) do
    serve(
      conn,
      "social/#{region_prefix(conn)}home-#{SocialImage.Home.version()}.jpg",
      &SocialImage.Home.draw/0
    )
  end

  def product(conn, %{"slug" => slug}) do
    case ProductPage.read(slug, DateTime.utc_now(), conn.assigns.region.market) do
      {:ok, page} ->
        key =
          "social/#{region_prefix(conn)}products/#{page.product.slug}-#{SocialImage.Product.version(page)}.jpg"

        serve(conn, key, fn -> SocialImage.Product.draw(page) end)

      :error ->
        conn |> put_resp_header("cache-control", "no-store") |> send_resp(404, "")
    end
  end

  def expensive_cards(conn, _params) do
    overview = Cards.Expensive.overview()
    version = SocialImage.ExpensiveCards.version(overview)

    serve(conn, "social/articles/najdrozsze-karty-pokemon-#{version}.jpg", fn ->
      SocialImage.ExpensiveCards.draw(overview)
    end)
  end

  def card_value(conn, _params) do
    guide = Cards.Value.guide()
    version = SocialImage.CardValue.version(guide)

    serve(conn, "social/articles/jak-sprawdzic-wartosc-karty-pokemon-#{version}.jpg", fn ->
      SocialImage.CardValue.draw(guide)
    end)
  end

  def cards(conn, _params) do
    market = Cards.SinglesBanner.market()

    serve(conn, "social/cards-#{SocialImage.Cards.version(market)}.jpg", fn ->
      SocialImage.Cards.draw(market)
    end)
  end

  def boosters(conn, _params) do
    page = BoosterGuide.prices(DateTime.utc_now())

    serve(conn, "social/boosters-#{SocialImage.BoosterPrices.version(page)}.jpg", fn ->
      SocialImage.BoosterPrices.draw(page)
    end)
  end

  # As the set page: the expansion under its current name only.
  def expansion(conn, %{"slug" => slug}) do
    with {:ok, id, name} <- known_expansion(slug),
         true <- slug == Catalogue.slug(name, id) do
      set_page = SetPage.read(id, name, DateTime.utc_now())
      version = SocialImage.Expansion.version(name, set_page)

      serve(conn, "social/expansions/#{slug}-#{version}.jpg", fn ->
        SocialImage.Expansion.draw(name, set_page)
      end)
    else
      _not_found -> not_found(conn)
    end
  end

  # As the card page: the card under its current path only.
  def card(conn, %{"slug" => set, "card_slug" => slug}) do
    path = "/rozszerzenia/#{set}/karty/#{slug}"

    with {:ok, _id, _name} <- known_expansion(set),
         {:ok, card, name, ^path} <- Cards.Guide.find(set, slug) do
      page = Cards.Guide.page(card, name, path)

      serve(conn, "social/cards/#{set}/#{slug}-#{SocialImage.Single.version(page)}.jpg", fn ->
        SocialImage.Single.draw(page)
      end)
    else
      _moved_or_missing -> not_found(conn)
    end
  end

  # An expansion id the cached names know, read without refreshing them: an
  # unknown id in a crawler's URL must not clear the cache for everyone.
  defp known_expansion(slug) do
    with {:ok, id} <- Paths.expansion_id(slug),
         {:ok, name} <- Map.fetch(Expansions.names(), id) do
      {:ok, id, name}
    else
      _unknown -> :error
    end
  end

  defp region_prefix(%{assigns: %{region: %{code: "pl"}}}), do: ""
  defp region_prefix(%{assigns: %{region: %{code: code}}}), do: code <> "/"

  defp not_found(conn),
    do: conn |> put_resp_header("cache-control", "no-store") |> send_resp(404, "")

  defp serve(conn, key, render) do
    {service, opts} = TcgCheap.Storage.service()

    case service.exists?(key, Context.new(opts)) do
      {:ok, true} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> redirect(external: service.url(key, Context.new(opts)))

      _missing ->
        render_and_store(conn, service, opts, key, render)
    end
  end

  defp render_and_store(conn, service, opts, key, render) do
    case render.() do
      {:ok, jpeg} ->
        store(service, opts, key, jpeg)

        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> send_resp(200, jpeg)

      # Drawn without a photo that failed to download: served, not kept.
      {:partial, jpeg} ->
        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> put_resp_header("cache-control", "public, max-age=300")
        |> send_resp(200, jpeg)

      {:error, :busy} ->
        conn
        |> put_resp_header("retry-after", "5")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(503, "")

      {:error, reason} ->
        Logger.error("Link-preview card #{key} failed: #{inspect(reason)}")
        conn |> put_resp_header("cache-control", "no-store") |> send_resp(500, "")
    end
  end

  # The card is still served when storing it fails; the next request retries.
  defp store(service, opts, key, jpeg) do
    context =
      Context.new(opts,
        content_type: "image/jpeg",
        expected_md5: :md5 |> :crypto.hash(jpeg) |> Base.encode64()
      )

    with {:error, reason} <- service.upload(key, jpeg, context),
         do: Logger.warning("Link-preview card #{key} not stored: #{inspect(reason)}")
  end
end
