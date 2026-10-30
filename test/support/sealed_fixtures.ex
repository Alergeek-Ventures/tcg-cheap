defmodule TcgCheap.SealedFixtures do
  @moduledoc """
  Helpers for buying-guide tests: trimmed real shop feeds and Cardmarket files,
  and stored rows.
  """

  alias TcgCheap.Pricing.CardmarketBulk.Adapter
  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Catalogue, CatalogueImport}

  @fixtures Path.expand("../fixtures/sealed", __DIR__)

  @doc "Decoded products from a trimmed real Store API response."
  def feed(shop), do: @fixtures |> Path.join("#{shop}.json") |> File.read!() |> Jason.decode!()

  @doc "The raw trimmed Cardmarket file (`:products` or `:prices`)."
  def cardmarket_file(:products),
    do: File.read!(Path.join(@fixtures, "cardmarket_nonsingles.json"))

  def cardmarket_file(:prices),
    do: File.read!(Path.join(@fixtures, "cardmarket_price_guide.json"))

  @doc "Catalogue rows built from the trimmed Cardmarket files."
  def cardmarket_rows do
    {:ok, products} = Adapter.parse_sealed_products(cardmarket_file(:products))
    {:ok, prices} = Adapter.parse_sealed_prices(cardmarket_file(:prices))
    Catalogue.rows(products.rows, prices.rows, ~D[2026-10-30])
  end

  @doc "Stubs one Store API page per call; `pages` is a list of product lists."
  def stub_feed(pages) when is_list(pages) do
    total = length(pages)

    Req.Test.stub(Sealed.WooCommerce, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      page = conn.query_params |> Map.get("page", "1") |> String.to_integer()

      conn
      |> Plug.Conn.put_resp_header("x-wp-totalpages", Integer.to_string(total))
      |> Req.Test.json(Enum.at(pages, page - 1, []))
    end)
  end

  @doc "Stubs both Cardmarket downloads with the trimmed real files."
  def stub_cardmarket(products \\ cardmarket_file(:products), prices \\ cardmarket_file(:prices)) do
    Req.Test.stub(CatalogueImport, fn conn ->
      body = if String.contains?(conn.request_path, "productList"), do: products, else: prices

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  @doc "Imports the trimmed real Cardmarket catalogue and returns products by name."
  def import_catalogue!(now \\ DateTime.utc_now()) do
    stub_cardmarket()

    {:ok, _} =
      CatalogueImport.run(now: now, request_options: [plug: {Req.Test, CatalogueImport}])

    Map.new(Sealed.list_products!(), &{&1.name, &1})
  end

  def product!(attrs \\ %{}) do
    attrs = Map.new(attrs)
    id = System.unique_integer([:positive])
    name = Map.get(attrs, :name, "Pitch Black Booster Box #{id}")

    defaults = %{
      cardmarket_id: id,
      name: name,
      kind: :booster_box,
      set_name: "Pitch Black",
      cardmarket_added_on: ~D[2026-04-30],
      slug: Catalogue.slug(name, id),
      search_text:
        Catalogue.search_text(
          name,
          Map.get(attrs, :set_name, "Pitch Black"),
          Map.get(attrs, :kind, :booster_box)
        )
    }

    Sealed.import_product!(Map.merge(defaults, Map.new(attrs)))
  end

  def offer!(attrs) do
    attrs = Map.new(attrs)

    defaults = %{
      shop: "colligere",
      shop_product_id: "#{System.unique_integer([:positive])}",
      title: "Pokémon TCG: Mega Evolution – Pitch Black – Booster Box",
      url: "https://colligere.pl/sklep/pokemon-tcg-mega-evolution-pitch-black-booster-box/",
      price: Decimal.new("799.94"),
      in_stock: true,
      last_seen_at: DateTime.utc_now()
    }

    offer = Sealed.upsert_offer!(Map.merge(defaults, Map.drop(attrs, [:product_id, :manual?])))

    case attrs do
      %{manual?: true, product_id: id} -> Sealed.assign_offer_manually!(offer, id)
      %{product_id: id} when not is_nil(id) -> Sealed.match_offer!(offer, id)
      _ -> offer
    end
  end

  def daily_price!(product_id, date, price, opts \\ []) do
    Sealed.record_shop_price!(%{
      product_id: product_id,
      date: date,
      lowest_price: price && Decimal.new(price),
      shops_in_stock: if(price, do: Keyword.get(opts, :shops, 1), else: 0)
    })

    if trend = opts[:cardmarket_trend] do
      Sealed.record_cardmarket_trend!(%{
        product_id: product_id,
        date: date,
        cardmarket_trend: Decimal.new(trend)
      })
    end

    :ok
  end

  def exchange_rate!(rate, date \\ Date.utc_today()) do
    TcgCheap.Core.record_exchange_rate!(%{
      rate: Decimal.new(rate),
      effective_date: date,
      publication_number: "#{System.unique_integer([:positive])}/A/NBP/2026",
      fetched_at: DateTime.utc_now()
    })
  end
end
