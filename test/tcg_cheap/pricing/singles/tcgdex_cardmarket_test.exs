defmodule TcgCheap.Pricing.Singles.TcgdexCardmarketTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.TcgdexCardmarket

  @fetched_at ~U[2026-08-07 12:00:00Z]
  @fixture_path Path.expand("../../../fixtures/tcgdex/base1-4.json", __DIR__)

  defp request_options(name), do: [plug: {Req.Test, name}, retry: false, max_retries: 0]

  defp stub_response(body, status \\ 200) do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      assert conn.request_path == "/v2/en/cards/base1-4"
      conn = Plug.Conn.put_status(conn, status)

      if is_binary(body) do
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Req.Test.text(body)
      else
        Req.Test.json(conn, body)
      end
    end)

    name
  end

  defp fetch_with(body, opts \\ []) do
    name = stub_response(body)

    TcgdexCardmarket.fetch(
      "base1-4",
      Keyword.merge([request_options: request_options(name), clock: fn -> @fetched_at end], opts)
    )
  end

  test "parses realistic fixture with deterministic provenance" do
    fixture = File.read!(@fixture_path)
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      assert conn.request_path == "/v2/en/cards/base1-4"
      conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      Req.Test.text(conn, fixture)
    end)

    assert {:ok, result} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )

    assert %TcgdexCardmarket.Result{
             card_id: "base1-4",
             value_eur: %Decimal{} = value,
             currency: :eur,
             policy_version: :tcgdex_cardmarket_v1,
             source: :tcgdex_cardmarket,
             source_metric: :avg7,
             fetched_at: @fetched_at,
             provider_updated_at: ~U[2026-08-07 08:03:04.828Z],
             cardmarket_product_id: 273_699
           } = result

    assert Decimal.equal?(value, Decimal.new("411.69"))
    refute Map.has_key?(result, :seller)
    refute Map.has_key?(result, :qualifying_seller_count)
    refute Map.has_key?(result, :seller_count)
    refute Map.has_key?(result, :offer_count)
  end

  for {metric, expected} <- [
        avg7: "411.69",
        avg30: "439.16",
        trend: "333.56",
        avg: "402.79",
        low: "99.95"
      ] do
    test "falls back to #{metric}" do
      metrics = [:avg7, :avg30, :trend, :avg, :low]
      selected_index = Enum.find_index(metrics, &(&1 == unquote(metric)))

      metric_json =
        Enum.map_join(Enum.with_index(metrics), ",", fn {candidate, index} ->
          value =
            cond do
              index < selected_index -> "null"
              index == selected_index -> unquote(expected)
              true -> Integer.to_string(1_000 + index)
            end

          ~s("#{candidate}":#{value})
        end)

      json =
        ~s({"id":"base1-4","pricing":{"cardmarket":{"unit":"EUR",#{metric_json}}}})

      name = stub_response(json)

      assert {:ok, result} =
               TcgdexCardmarket.fetch("base1-4",
                 request_options: request_options(name),
                 clock: fn -> @fetched_at end
               )

      assert result.source_metric == unquote(metric)
      assert Decimal.equal?(result.value_eur, Decimal.new(unquote(expected)))
    end
  end

  test "converts integer metrics to Decimal" do
    assert {:ok, result} =
             fetch_with(%{
               "id" => "base1-4",
               "pricing" => %{"cardmarket" => %{"unit" => "EUR", "avg7" => 12}}
             })

    assert result.source_metric == :avg7
    assert Decimal.equal?(result.value_eur, Decimal.new("12.00"))
  end

  test "rounds raw numeric JSON half up without float arithmetic" do
    name =
      stub_response(~s({"id":"base1-4","pricing":{"cardmarket":{"unit":"EUR","avg7":1.235}}}))

    assert {:ok, result} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )

    assert Decimal.equal?(result.value_eur, Decimal.new("1.24"))
  end

  test "skips nil, strings, malformed, zero, and negative metrics" do
    cardmarket = %{
      "unit" => "EUR",
      "avg7" => nil,
      "avg30" => "bad",
      "trend" => %{},
      "avg" => 0,
      "low" => -1
    }

    assert {:error, :unavailable_pricing} =
             fetch_with(%{"id" => "base1-4", "pricing" => %{"cardmarket" => cardmarket}})
  end

  test "skips values that cannot be rounded and falls back to the next metric" do
    name =
      stub_response(
        ~s({"id":"base1-4","pricing":{"cardmarket":{"unit":"EUR","avg7":1e6145,"avg30":12.345}}})
      )

    assert {:ok, result} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )

    assert result.source_metric == :avg30
    assert Decimal.equal?(result.value_eur, Decimal.new("12.35"))
  end

  test "returns unavailable for missing or nil Cardmarket pricing" do
    assert {:error, :unavailable_pricing} = fetch_with(%{"id" => "base1-4", "pricing" => %{}})

    assert {:error, :unavailable_pricing} =
             fetch_with(%{"id" => "base1-4", "pricing" => %{"cardmarket" => nil}})
  end

  test "returns malformed response for malformed pricing shape" do
    name = stub_response(~s({"id":"base1-4","pricing":{"cardmarket":[]}}))

    assert {:error, {:malformed_response, :invalid_cardmarket}} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )
  end

  test "returns unsupported currency for missing unit" do
    assert {:error, {:unsupported_currency, nil}} =
             fetch_with(%{"id" => "base1-4", "pricing" => %{"cardmarket" => %{"avg7" => 1}}})
  end

  test "preserves unsupported currency unit" do
    assert {:error, {:unsupported_currency, "USD"}} =
             fetch_with(%{
               "id" => "base1-4",
               "pricing" => %{"cardmarket" => %{"unit" => "USD", "avg7" => 1}}
             })
  end

  test "handles malformed identity, timestamp, and product id" do
    body = %{
      "id" => "base1-4",
      "pricing" => %{
        "cardmarket" => %{
          "unit" => "EUR",
          "avg7" => 1,
          "updated" => "not-a-date",
          "idProduct" => -1
        }
      }
    }

    assert {:ok, result} = fetch_with(body)
    assert result.provider_updated_at == nil
    assert result.cardmarket_product_id == nil
    name = stub_response(%{"id" => "other", "pricing" => %{}})

    assert {:error, {:malformed_response, {:card_id_mismatch, "base1-4", "other"}}} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )
  end

  test "invalid card IDs and options do not make HTTP requests" do
    assert {:error, :invalid_card_id} = TcgdexCardmarket.fetch("   ", [])
    assert {:error, :invalid_card_id} = TcgdexCardmarket.fetch(123, [])
    assert {:error, :invalid_options} = TcgdexCardmarket.fetch("base1-4", %{})
    assert {:error, :invalid_options} = TcgdexCardmarket.fetch("base1-4", request_options: %{})
    assert {:error, :invalid_options} = TcgdexCardmarket.fetch("base1-4", clock: :now)

    assert {:error, :invalid_options} =
             fetch_with(
               %{
                 "id" => "base1-4",
                 "pricing" => %{"cardmarket" => %{"unit" => "EUR", "avg7" => 1}}
               },
               clock: fn -> :not_datetime end
             )
  end

  test "returns invalid options when the clock raises" do
    assert {:error, :invalid_options} =
             fetch_with(
               %{
                 "id" => "base1-4",
                 "pricing" => %{"cardmarket" => %{"unit" => "EUR", "avg7" => 1}}
               },
               clock: fn -> raise "clock failed" end
             )
  end

  test "rejects unsafe or duplicate request options before HTTP" do
    invalid_options = [
      [url: "https://attacker.invalid"],
      [base_url: "https://attacker.invalid"],
      [method: :post],
      [adapter: :finch],
      [decoders: []],
      [retry: :transient],
      [retry: true],
      [max_retries: 3],
      [plug: make_ref(), plug: make_ref()]
    ]

    for request_options <- invalid_options do
      assert {:error, :invalid_options} =
               TcgdexCardmarket.fetch("base1-4",
                 request_options: request_options,
                 clock: fn -> @fetched_at end
               )
    end
  end

  for {status, tag} <- [{404, :not_found}, {429, :rate_limited}, {500, :http_error}] do
    test "classifies HTTP #{status}" do
      name = stub_response(%{}, unquote(status))

      assert {:error, {unquote(tag), %{status: unquote(status), card_id: "base1-4"}}} =
               TcgdexCardmarket.fetch("base1-4",
                 request_options: request_options(name),
                 clock: fn -> @fetched_at end
               )
    end
  end

  test "classifies malformed JSON decode errors" do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      conn = Plug.Conn.put_resp_header(conn, "content-type", "application/json")
      Req.Test.text(conn, ~s({))
    end)

    assert {:error, {:decode_error, %Jason.DecodeError{}}} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )
  end

  test "classifies malformed JSON on non-200 responses by HTTP status" do
    name = stub_response(~s({), 404)

    assert {:error, {:not_found, %{status: 404, card_id: "base1-4"}}} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )
  end

  test "classifies transport errors" do
    name = make_ref()
    Req.Test.stub(name, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, {:transport_error, _}} =
             TcgdexCardmarket.fetch("base1-4",
               request_options: request_options(name),
               clock: fn -> @fetched_at end
             )
  end
end
