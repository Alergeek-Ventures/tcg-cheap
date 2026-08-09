defmodule TcgCheapWeb.AdminLoginLimiterTest do
  use ExUnit.Case, async: false

  alias TcgCheapWeb.AdminLoginLimiter

  test "limits distributed addresses for one normalized account" do
    email = "  Admin-#{System.unique_integer([:positive])}@Example.TEST  "
    addresses = for octet <- 1..5, do: {10, 20, 30, octet}

    for address <- addresses, do: assert(:ok = AdminLoginLimiter.reserve(address, email))
    assert {:error, retry_after} = AdminLoginLimiter.reserve({10, 20, 30, 99}, email)
    assert retry_after > 0

    for address <- addresses, do: assert(:ok = AdminLoginLimiter.clear(address, email))
  end

  test "limits one address across identities and clears both keys" do
    address = {10, 20, 30, rem(System.unique_integer([:positive]), 254) + 1}

    for index <- 1..5 do
      assert :ok = AdminLoginLimiter.reserve(address, "admin-#{index}@example.test")
    end

    assert {:error, retry_after} = AdminLoginLimiter.reserve(address, "other@example.test")
    assert retry_after > 0

    assert :ok = AdminLoginLimiter.clear(address, "admin-1@example.test")
    assert :ok = AdminLoginLimiter.reserve(address, "other@example.test")
    assert :ok = AdminLoginLimiter.clear(address, "other@example.test")
  end

  test "fails closed at the bounded key capacity without growing state" do
    limiter =
      start_supervised!(
        {AdminLoginLimiter,
         name: nil, limit: 5, window_ms: 60_000, max_entries: 2, prune_interval_ms: 60_000}
      )

    assert :ok = AdminLoginLimiter.reserve(limiter, {192, 0, 2, 1}, "first@example.test")

    assert {:error, retry_after} =
             AdminLoginLimiter.reserve(limiter, {192, 0, 2, 2}, "second@example.test")

    assert retry_after > 0
    assert :ok = AdminLoginLimiter.clear(limiter, {192, 0, 2, 1}, "first@example.test")
    assert :ok = AdminLoginLimiter.reserve(limiter, {192, 0, 2, 2}, "second@example.test")
  end
end
