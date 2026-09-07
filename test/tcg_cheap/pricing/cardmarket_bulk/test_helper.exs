defmodule TcgCheap.Pricing.CardmarketBulk.TestHelper do
  alias TcgCheap.Pricing.CardmarketBulk.Adapter

  @products_url "https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_6.json"
  @prices_url "https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_6.json"

  def adapter_options(fixture), do: [request_options: [fixture: fixture]]

  def product_url, do: @products_url
  def price_url, do: @prices_url

  def result(kind, :invalid_product, opts) do
    result(kind, opts, product_name: "")
  end

  def result(kind, :mismatch, opts), do: result(kind, opts, price_id: unique_id() + 1)

  def result(kind, :good, opts), do: result(kind, opts, kind: kind)
  def result(kind, :unavailable, opts), do: result(kind, opts, kind: kind, unavailable: true)

  def result(kind, {:anomaly, key}, opts) do
    anomaly_result(kind, key, opts)
  end

  def result(kind, {:sha, product_sha, price_sha}, opts) do
    result(kind, opts, kind: kind)
    |> Map.put(:sha256, if(kind == :products, do: product_sha, else: price_sha))
  end

  def result(kind, {:rows, count}, opts) do
    result(kind, opts, kind: kind, row_count: count)
  end

  def result(kind, opts, overrides) do
    request_options = Keyword.get(opts, :request_options, [])
    id = Keyword.get(overrides, :id, Keyword.get(request_options, :product_id, unique_id()))
    product_id = Keyword.get(overrides, :price_id, id)

    created_at =
      Keyword.get(
        overrides,
        :created_at,
        Keyword.get(request_options, :created_at, ~U[2026-09-03 10:00:00Z])
      )

    fetched_at = Keyword.get(opts, :clock, fn -> ~U[2026-09-03 12:00:00Z] end).()
    name = Keyword.get(overrides, :product_name, "Fixture #{id}")
    kind = Keyword.get(overrides, :kind, kind)

    row_count = Keyword.get(overrides, :row_count, 1)

    %Adapter{
      raw_body: "#{kind}-body-#{id}",
      sha256: hash("#{kind}-body-#{id}"),
      byte_size: byte_size("#{kind}-body-#{id}"),
      fetched_at: fetched_at,
      created_at: created_at,
      total_rows: row_count,
      source_rows: row_count,
      priceable_count: if(kind == :prices, do: row_count, else: 0),
      rows:
        for offset <- 0..(row_count - 1) do
          row(
            kind,
            id + offset,
            product_id + offset,
            name,
            Keyword.get(overrides, :unavailable, false)
          )
        end
    }
  end

  defp row(:products, id, _price_id, name, _unavailable) do
    %Adapter.Product{
      id_product: id,
      name: name,
      category: "Pokémon Single",
      category_id: 51,
      id_expansion: 2,
      id_metacard: 0,
      date_added: "2026-09-03"
    }
  end

  defp row(:prices, _id, price_id, _name, false) do
    %Adapter.Price{
      id_product: price_id,
      category_id: 51,
      avg7: Decimal.new("12.34"),
      selected_metric: :avg7,
      selected_value: Decimal.new("12.34")
    }
  end

  defp row(:prices, _id, price_id, _name, true) do
    %Adapter.Price{id_product: price_id, category_id: 51}
  end

  defp hash(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  defp anomaly_result(kind, key, opts) when key in [:product_row_count, :price_row_count] do
    value = result(kind, opts, kind: kind)

    if (key == :product_row_count and kind == :products) or
         (key == :price_row_count and kind == :prices) do
      Map.put(value, :total_rows, 2)
    else
      value
    end
  end

  defp anomaly_result(kind, :singles_price_row_count, opts) do
    result(kind, opts, kind: kind, row_count: 2) |> Map.put(:total_rows, 1)
  end

  defp anomaly_result(kind, :priceable_singles_count, opts) do
    result(kind, opts, kind: kind) |> Map.put(:priceable_count, 2)
  end

  defp unique_id, do: System.unique_integer([:positive])
end

defmodule TcgCheap.Pricing.CardmarketBulk.FakeAdapter do
  alias TcgCheap.Pricing.CardmarketBulk.TestHelper

  def fetch_products(opts) do
    record(opts)
    {:ok, result(:products, opts)}
  end

  def fetch_prices(opts) do
    record(opts)
    {:ok, result(:prices, opts)}
  end

  defp result(kind, opts) do
    TestHelper.result(kind, fixture(opts), opts)
  end

  defp fixture(opts), do: Keyword.get(Keyword.get(opts, :request_options, []), :fixture, :good)

  defp record(opts) do
    Keyword.fetch!(opts, :request_admitter).()

    send(
      self(),
      {:fake_adapter_admitted, Keyword.get(Keyword.get(opts, :request_options, []), :fixture)}
    )
  end
end
