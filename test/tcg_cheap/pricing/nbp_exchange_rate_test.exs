defmodule TcgCheap.Pricing.NbpExchangeRateTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.{ExchangeRateProvider, NbpExchangeRate}

  @fetched_at ~U[2026-08-08 12:00:00Z]
  @fixture Path.expand("../../fixtures/nbp/latest_eur.json", __DIR__)

  defp fetch(body, status \\ 200, opts \\ []) do
    name = make_ref()

    Req.Test.stub(name, fn conn ->
      assert conn.scheme == :https
      assert conn.request_path == "/api/exchangerates/rates/a/eur/"
      conn = Plug.Conn.put_status(conn, status)
      if is_binary(body), do: Req.Test.text(conn, body), else: Req.Test.json(conn, body)
    end)

    NbpExchangeRate.fetch(
      canonical_request(),
      Keyword.merge(
        [plug: {Req.Test, name}, retry: false, max_retries: 0, clock: fn -> @fetched_at end],
        opts
      )
    )
  end

  defp canonical_request do
    %{"source" => "nbp", "table" => "A", "base_currency" => "EUR", "quote_currency" => "PLN"}
  end

  test "returns typed result and preserves decimal precision" do
    assert {:ok, %ExchangeRateProvider.Result{} = result} = fetch(File.read!(@fixture))
    assert result.rate == Decimal.new("4.3010")
    assert result.publication_number == "152/A/NBP/2026"
    assert result.effective_date == ~D[2026-08-07]
    assert result.fetched_at == @fetched_at
  end

  test "rejects non-canonical requests without invoking clock or HTTP" do
    clock = fn -> raise "clock must not be called" end

    for request <- [
          %{},
          %{"source" => "nbp", "table" => "A", "base_currency" => "EUR"},
          %{
            "source" => "other",
            "table" => "A",
            "base_currency" => "EUR",
            "quote_currency" => "PLN"
          },
          %{
            "source" => "nbp",
            "table" => "A",
            "base_currency" => "EUR",
            "quote_currency" => "PLN",
            "extra" => true
          },
          nil,
          :request
        ] do
      assert {:error, :invalid_request} =
               NbpExchangeRate.fetch(request, clock: clock, plug: {Req.Test, make_ref()})
    end
  end

  test "uses the supplied clock and rejects malformed payloads" do
    assert {:error, :malformed_json} = fetch("{")
    assert {:error, :malformed_shape} = fetch(%{"table" => "B"})
    assert {:error, :malformed_shape} = fetch(%{"table" => "A", "code" => "USD", "rates" => []})
    assert {:error, :malformed_shape} = fetch(%{"table" => "A", "code" => "EUR", "rates" => []})

    assert {:error, :malformed_shape} =
             fetch(%{"table" => "A", "code" => "EUR", "rates" => [%{}, %{}]})
  end

  for {label, publication, rate} <- [
        {"empty publication", "", 4},
        {"zero", "zero", 0},
        {"negative", "negative", -1},
        {"string", "string", "4.3"}
      ] do
    test "rejects #{label} rates" do
      body = %{
        "table" => "A",
        "code" => "EUR",
        "rates" => [
          %{"no" => unquote(publication), "effectiveDate" => "2026-08-07", "mid" => unquote(rate)}
        ]
      }

      assert {:error, _} = fetch(body)
    end
  end

  test "rejects invalid dates and future observations" do
    base = %{
      "table" => "A",
      "code" => "EUR",
      "rates" => [%{"no" => "1", "effectiveDate" => "2026-08-09", "mid" => 4}]
    }

    assert {:error, :invalid_rate} = fetch(base)
    bad_date = update_in(base, ["rates", Access.at(0), "effectiveDate"], fn _ -> "bad" end)
    assert {:error, :invalid_rate} = fetch(bad_date)
  end

  test "classifies HTTP and transport failures" do
    assert {:error, :no_published_rate} = fetch("", 404)
    assert {:error, {:rate_limited, %{status: 429}}} = fetch("", 429)
    assert {:error, {:http_error, %{status: 500}}} = fetch("", 500)
  end

  test "classifies a request callback exception as transport failure" do
    name = make_ref()
    Req.Test.stub(name, fn _conn -> raise "callback boom" end)

    assert {:error, {:transport_error, _exception}} =
             NbpExchangeRate.fetch(canonical_request(),
               plug: {Req.Test, name},
               retry: false,
               max_retries: 0,
               clock: fn -> @fetched_at end
             )
  end

  test "trims nonempty publication numbers" do
    body = %{
      "table" => "A",
      "code" => "EUR",
      "rates" => [%{"no" => " 154/A/NBP/2026 ", "effectiveDate" => "2026-08-07", "mid" => 4.3010}]
    }

    assert {:ok, result} = fetch(body)
    assert result.publication_number == "154/A/NBP/2026"
  end

  test "validates options, including duplicate keys and clock" do
    assert {:error, :invalid_options} =
             NbpExchangeRate.fetch(canonical_request(), retry: :safe, retry: false)

    assert {:error, :invalid_options} = NbpExchangeRate.fetch(canonical_request(), max_retries: 3)
    assert {:error, :invalid_options} = NbpExchangeRate.fetch(canonical_request(), retry: :never)
    assert {:error, :invalid_clock} = fetch(File.read!(@fixture), 200, clock: :bad)
  end
end
