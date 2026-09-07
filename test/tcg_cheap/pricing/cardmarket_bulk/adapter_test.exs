defmodule TcgCheap.Pricing.CardmarketBulk.AdapterTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.CardmarketBulk.Adapter

  @created "2026-09-03T12:00:00+0200"

  defp product(overrides \\ %{}) do
    Map.merge(
      %{
        "idProduct" => 1,
        "idCategory" => 51,
        "categoryName" => "Pokémon Single",
        "name" => "Pikachu",
        "idExpansion" => 2,
        "idMetacard" => 0,
        "dateAdded" => "0000-00-00"
      },
      overrides
    )
  end

  defp envelope(key, rows),
    do: Jason.encode!(%{"version" => 1, "createdAt" => @created, key => rows})

  defp price(overrides), do: Map.merge(%{"idProduct" => 1, "idCategory" => 51}, overrides)
  defp parse_price(row), do: Adapter.parse_prices(envelope("priceGuides", [row]))
  defp opts(name), do: [request_options: [plug: {Req.Test, name}]]

  test "parses production product fields and preserves dateAdded source text" do
    assert {:ok, %{rows: [%Adapter.Product{} = row]}} =
             Adapter.parse_products(envelope("products", [product()]))

    assert row.category == "Pokémon Single"
    assert row.date_added == "0000-00-00"
    refute Map.has_key?(row, :raw)
  end

  test "requires a nonblank string dateAdded for products" do
    for row <- [
          Map.delete(product(), "dateAdded"),
          product(%{"dateAdded" => 42}),
          product(%{"dateAdded" => "   "})
        ] do
      assert {:error, {:malformed, {:blank, "dateAdded"}}} =
               Adapter.parse_products(envelope("products", [row]))
    end
  end

  test "persists the normalized nonblank dateAdded value" do
    assert {:ok, %{rows: [%Adapter.Product{date_added: "2026-09-03"}]}} =
             Adapter.parse_products(
               envelope("products", [product(%{"dateAdded" => " 2026-09-03 "})])
             )
  end

  test "accepts documented category aliases" do
    assert {:ok, _} =
             Adapter.parse_products(
               envelope("products", [
                 product(%{
                   "categoryId" => 51,
                   "category" => "Pokémon Single",
                   "idCategory" => nil,
                   "categoryName" => nil
                 })
               ])
             )
  end

  test "filters combined non-single guides and reports all counts" do
    rows = [
      price(%{"idProduct" => 1, "avg7" => "2.00"}),
      price(%{"idProduct" => 2, "idCategory" => 1, "avg7" => "99"}),
      price(%{"idProduct" => 3})
    ]

    assert {:ok, result} = Adapter.parse_prices(envelope("priceGuides", rows))
    assert {result.total_rows, result.source_rows, result.priceable_count} == {3, 2, 1}
  end

  test "normalizes null and zero metrics and allows unavailable prices" do
    assert {:ok, %{rows: [%Adapter.Price{selected_value: nil, avg: nil, low: nil}]}} =
             parse_price(price(%{"avg" => 0, "low" => nil, "trend" => 0.0}))
  end

  test "selects every priority metric when earlier values are unavailable" do
    Enum.each(
      [{"avg7", :avg7}, {"avg30", :avg30}, {"trend", :trend}, {"avg", :avg}, {"low", :low}],
      fn {field, metric} ->
        values = %{"avg7" => nil, "avg30" => nil, "trend" => nil, "avg" => nil, "low" => nil}

        assert {:ok, %{rows: [%{selected_metric: ^metric}]}} =
                 parse_price(price(Map.put(values, field, "1")))
      end
    )
  end

  test "rejects duplicate IDs globally, including filtered rows" do
    rows = [price(%{"idProduct" => 9, "idCategory" => 1}), price(%{"idProduct" => 9})]

    assert {:error, {:malformed, {:duplicate_id_product, 9}}} =
             Adapter.parse_prices(envelope("priceGuides", rows))
  end

  test "rejects invalid product fields" do
    for change <- [
          %{"idProduct" => 0},
          %{"name" => " "},
          %{"idExpansion" => 0},
          %{"idMetacard" => -1},
          %{"idCategory" => 1},
          %{"categoryName" => "Pokemon Single"}
        ] do
      assert {:error, {:malformed, _}} =
               Adapter.parse_products(envelope("products", [product(change)]))
    end
  end

  test "rejects invalid timestamp, version, shape and JSON" do
    assert {:error, {:malformed, :invalid_created_at}} =
             Adapter.parse_products(
               envelope("products", [product()])
               |> String.replace(@created, "bad")
             )

    assert {:error, {:malformed, {:invalid_version, 2}}} =
             Adapter.parse_products(
               String.replace(envelope("products", []), "\"version\":1", "\"version\":2")
             )

    assert {:error, {:decode_error, _}} = Adapter.parse_products("not json")

    assert {:error, {:malformed, _}} =
             Adapter.parse_products(Jason.encode!(%{"version" => 1, "createdAt" => @created}))
  end

  test "rejects invalid options and clock" do
    body = envelope("products", [])
    assert {:error, :invalid_options} = Adapter.parse_products(body, clock: :bad)

    assert {:error, :invalid_clock} =
             Adapter.parse_products(body, clock: fn -> :not_a_date end)

    assert {:error, :invalid_options} =
             Adapter.fetch_products(request_options: [url: "https://evil.invalid"])
  end

  test "rejects negative and malformed numbers" do
    for value <- [-1, "-1", "NaN", "Infinity", "wat"] do
      assert {:error, {:malformed, {:invalid_number, _}}} = parse_price(price(%{"avg7" => value}))
    end
  end

  test "direct parsing rejects oversized body without decoding" do
    assert {:error, {:oversized, 33_554_432}} =
             Adapter.parse_products(:binary.copy(<<"x">>, 33_554_433))
  end

  test "rejects source cardinality above the bounded row cap before row parsing" do
    rows = List.duplicate(%{}, 100_001)

    assert {:error, {:malformed, {:too_many_rows, 100_001}}} =
             Adapter.parse_products(envelope("products", rows))
  end

  test "bounds streamed HTTP responses" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)

      Enum.reduce_while(1..33, conn, fn _, conn ->
        case Plug.Conn.chunk(conn, :binary.copy(<<"x">>, 1_048_576)) do
          {:ok, conn} -> {:cont, conn}
          {:error, reason} -> {:halt, flunk("unexpected chunk error: #{inspect(reason)}")}
        end
      end)
    end)

    assert {:error, {:oversized, 33_554_432}} = Adapter.fetch_products(opts(name))
  end

  test "requires one parseable JSON content type for successful responses" do
    body = envelope("products", [])

    for content_type <- [
          "text/plain",
          "text/html",
          "application/octet-stream",
          "application/json; charset"
        ] do
      name = make_ref()

      Req.Test.stub(name, fn conn ->
        conn = Plug.Conn.put_resp_header(conn, "content-type", content_type)
        Plug.Conn.send_resp(conn, 200, "not json")
      end)

      assert {:error, {:malformed, :invalid_content_type}} = Adapter.fetch_products(opts(name))
    end

    duplicate = make_ref()

    Req.Test.stub(duplicate, fn conn ->
      conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      conn = update_in(conn.resp_headers, &[{"content-type", "application/json"} | &1])
      Plug.Conn.send_resp(conn, 200, body)
    end)

    assert {:error, {:malformed, :invalid_content_type}} = Adapter.fetch_products(opts(duplicate))
  end

  test "accepts JSON content type with and without charset" do
    for content_type <- ["application/json", "Application/JSON; charset=utf-8"] do
      name = make_ref()

      Req.Test.stub(name, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", content_type)
        |> Plug.Conn.send_resp(200, envelope("products", []))
      end)

      assert {:ok, _} = Adapter.fetch_products(opts(name))
    end
  end

  test "classifies HTTP statuses and rejects redirects" do
    for {status, reason} <- [
          {404, :not_found},
          {429, :rate_limited},
          {500, {:unexpected_status, 500}},
          {302, {:unexpected_status, 302}}
        ] do
      name = make_ref()
      Req.Test.stub(name, fn conn -> Plug.Conn.send_resp(conn, status, "") end)
      assert {:error, {:http_error, ^reason}} = Adapter.fetch_products(opts(name))
    end
  end

  test "classifies transport timeout and transport errors" do
    timeout = make_ref()
    Req.Test.stub(timeout, &Req.Test.transport_error(&1, :timeout))
    assert {:error, {:timeout, :request}} = Adapter.fetch_products(opts(timeout))
    failure = make_ref()
    Req.Test.stub(failure, &Req.Test.transport_error(&1, :closed))
    assert {:error, {:transport_error, :closed}} = Adapter.fetch_products(opts(failure))
  end

  test "admission rejection, raise and throw prevent HTTP invocation" do
    name = make_ref()
    Req.Test.stub(name, fn _ -> flunk("request was admitted") end)

    for admission <- [
          fn -> {:error, :rejected} end,
          fn -> raise "boom" end,
          fn -> throw(:boom) end
        ] do
      assert {:error, _} = Adapter.fetch_products(opts(name) ++ [request_admitter: admission])
    end
  end

  test "uses both fixed endpoint paths" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      body =
        if conn.request_path =~ "productList",
          do: envelope("products", []),
          else: envelope("priceGuides", [])

      Req.Test.json(conn, Jason.decode!(body))
    end)

    assert {:ok, _} = Adapter.fetch_products(opts(name))
    assert {:ok, _} = Adapter.fetch_prices(opts(name))
  end
end
