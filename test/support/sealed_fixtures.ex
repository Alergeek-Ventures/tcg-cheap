defmodule TcgCheap.SealedFixtures do
  @moduledoc "Helpers for buying-guide tests: real feed fixtures and stored rows."

  alias TcgCheap.Sealed

  @fixtures Path.expand("../fixtures/sealed", __DIR__)

  @doc "Decoded products from a trimmed real Store API response."
  def feed(shop), do: @fixtures |> Path.join("#{shop}.json") |> File.read!() |> Jason.decode!()

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

  def offer!(attrs) do
    defaults = %{
      shop: "colligere",
      shop_product_id: "#{System.unique_integer([:positive])}",
      title: "Pokémon TCG: Pitch Black – Booster",
      url: "https://colligere.pl/sklep/pokemon-tcg-pitch-black-booster/",
      price: Decimal.new("24.95"),
      in_stock: true,
      product_slug: "pokemon-tcg-pitch-black-booster-pack",
      last_seen_at: DateTime.utc_now()
    }

    Sealed.upsert_offer!(Map.merge(defaults, Map.new(attrs)))
  end

  def daily_price!(slug, date, price, shops \\ 1) do
    Sealed.record_daily_price!(%{
      product_slug: slug,
      date: date,
      lowest_price: price && Decimal.new(price),
      shops_in_stock: if(price, do: shops, else: 0)
    })
  end
end
