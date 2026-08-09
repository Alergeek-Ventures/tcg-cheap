defmodule TcgCheapWeb.PublicAcquisitionLimiterTest do
  use ExUnit.Case, async: true

  alias TcgCheapWeb.PublicAcquisitionLimiter

  setup do
    {:ok, server} =
      start_supervised(
        {PublicAcquisitionLimiter,
         name: nil, limit: 2, window_ms: 100, max_entries: 2, prune_interval_ms: 10_000}
      )

    {:ok, server: server}
  end

  test "isolates IPv4 and IPv6 and rejects at the exact boundary", %{server: server} do
    ipv4 = {198, 51, 100, 1}
    ipv6 = {0, 0, 0, 0, 0, 0, 0, 1}

    assert :ok = PublicAcquisitionLimiter.reserve(server, ipv4)
    assert :ok = PublicAcquisitionLimiter.reserve(server, ipv4)

    assert {:error, {:public_acquisition_rate_limited, retry}} =
             PublicAcquisitionLimiter.reserve(server, ipv4)

    assert retry >= 1
    assert :ok = PublicAcquisitionLimiter.reserve(server, ipv6)
  end

  test "rejects invalid addresses and reclaims expired capacity", %{server: server} do
    assert {:error, :invalid_address} = PublicAcquisitionLimiter.reserve(server, :not_an_address)
    assert :ok = PublicAcquisitionLimiter.reserve(server, {192, 0, 2, 1})
    assert :ok = PublicAcquisitionLimiter.reserve(server, {192, 0, 2, 2})

    assert {:error, {:public_acquisition_rate_limited, _}} =
             PublicAcquisitionLimiter.reserve(server, {192, 0, 2, 3})

    Process.sleep(120)
    assert :ok = PublicAcquisitionLimiter.reserve(server, {192, 0, 2, 3})
  end

  test "serializes concurrent reservations", %{server: server} do
    address = {203, 0, 113, 9}

    results =
      Task.async_stream(1..20, fn _ -> PublicAcquisitionLimiter.reserve(server, address) end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 2
    assert Enum.count(results, &match?({:error, {:public_acquisition_rate_limited, _}}, &1)) == 18
  end
end
