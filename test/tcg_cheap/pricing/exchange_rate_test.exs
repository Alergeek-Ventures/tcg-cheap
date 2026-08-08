defmodule TcgCheap.Pricing.ExchangeRateTest do
  use TcgCheap.DataCase, async: true

  alias TcgCheap.Core

  @fetched_at ~U[2026-08-08 12:00:00Z]

  defp observation(overrides \\ %{}) do
    Map.merge(
      %{
        source: "nbp",
        table: "A",
        base_currency: "EUR",
        quote_currency: "PLN",
        rate: Decimal.new("4.3010"),
        effective_date: Date.add(~D[2000-01-01], -System.unique_integer([:positive])),
        publication_number: "pub-#{System.unique_integer([:positive])}",
        fetched_at: @fetched_at
      },
      overrides
    )
  end

  test "records a valid Decimal observation" do
    assert {:ok, rate} = Core.record_exchange_rate(observation())
    assert %Decimal{} = rate.rate
    assert Decimal.equal?(rate.rate, Decimal.new("4.3010"))
  end

  test "upserts the canonical effective date and retains distinct dates" do
    first = observation(%{rate: Decimal.new("4.30")})

    second = %{
      first
      | rate: Decimal.new("4.40"),
        publication_number: "pub-#{System.unique_integer([:positive])}",
        fetched_at: ~U[2026-08-08 13:00:00Z]
    }

    assert {:ok, _} = Core.record_exchange_rate(first)
    assert {:ok, updated} = Core.record_exchange_rate(second)
    assert updated.publication_number == second.publication_number
    assert DateTime.compare(updated.fetched_at, second.fetched_at) == :eq
    assert {:ok, history} = Core.list_exchange_rate_history(~D[2026-08-08])
    assert length(history) == 1
    assert Decimal.equal?(hd(history).rate, Decimal.new("4.40"))

    assert {:ok, _} = Core.record_exchange_rate(%{first | effective_date: ~D[2026-08-06]})
    assert {:ok, history} = Core.list_exchange_rate_history(~D[2026-08-08])
    assert Enum.map(history, & &1.effective_date) == [~D[2026-08-06], first.effective_date]
  end

  test "history defaults to 90 observations and enforces its maximum" do
    assert {:ok, []} = Core.list_exchange_rate_history(~D[2026-08-08], 90)
    assert {:error, %Ash.Error.Invalid{}} = Core.list_exchange_rate_history(~D[2026-08-08], 0)
    assert {:error, %Ash.Error.Invalid{}} = Core.list_exchange_rate_history(~D[2026-08-08], 367)
  end

  test "latest uses effective date, not fetched time, and as_of excludes future dates" do
    assert {:ok, _} =
             Core.record_exchange_rate(
               observation(%{
                 effective_date: ~D[2026-08-05],
                 fetched_at: ~U[2026-08-08 23:00:00Z]
               })
             )

    assert {:ok, _} =
             Core.record_exchange_rate(
               observation(%{
                 effective_date: ~D[2026-08-07],
                 fetched_at: ~U[2026-08-07 01:00:00Z]
               })
             )

    assert {:ok, latest} = Core.get_latest_exchange_rate(~D[2026-08-08])
    assert latest.effective_date == ~D[2026-08-07]
    assert {:ok, nil} = Core.get_latest_exchange_rate(~D[2026-08-04])
    assert {:ok, latest} = Core.get_latest_exchange_rate(~D[2026-08-06])
    assert latest.effective_date == ~D[2026-08-05]
    assert {:ok, nil} = Core.get_latest_exchange_rate(~D[2026-08-04])
  end

  test "rejects invalid canonical fields, rates, and publication numbers" do
    for {field, value} <- [source: "x", table: "B", base_currency: "USD", quote_currency: "USD"] do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.record_exchange_rate(observation(%{field => value}))
    end

    for rate <- [Decimal.new(0), Decimal.new("-1")] do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.record_exchange_rate(observation(%{rate: rate}))
    end

    for publication <- ["", "   "] do
      assert {:error, %Ash.Error.Invalid{}} =
               Core.record_exchange_rate(observation(%{publication_number: publication}))
    end
  end
end
