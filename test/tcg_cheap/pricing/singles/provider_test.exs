defmodule TcgCheap.Pricing.Singles.ProviderTest do
  use ExUnit.Case, async: true

  alias TcgCheap.Pricing.Singles.Provider

  test "required capabilities are sorted and stable" do
    assert Provider.required_capabilities() == [
             :condition,
             :destination_shipping,
             :language,
             :price_eur,
             :seller_identity
           ]
  end

  test "reports seller identity and destination shipping gaps deterministically" do
    expected = [
      :condition,
      :destination_shipping,
      :seller_identity
    ]

    assert Provider.missing_required_capabilities([:price_eur, :language]) == expected
    assert Provider.missing_required_capabilities([:language, :price_eur, :price_eur]) == expected

    assert Provider.missing_required_capabilities([:unknown, :price_eur, :language]) == expected

    assert Provider.missing_required_capabilities([
             :seller_identity,
             :destination_shipping,
             :condition,
             :language,
             :price_eur,
             :unknown,
             :seller_identity
           ]) == []
  end
end
