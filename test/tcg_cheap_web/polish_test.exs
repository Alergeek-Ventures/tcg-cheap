defmodule TcgCheapWeb.PolishTest do
  use ExUnit.Case, async: true

  alias TcgCheapWeb.Polish

  test "prices use a decimal comma, grouped thousands and no-break spaces" do
    assert Polish.price(Decimal.new("1299.99")) == "1 299,99 zł"
    assert Polish.price(Decimal.new("24.95")) == "24,95 zł"
    assert Polish.price(Decimal.new("150")) == "150,00 zł"
    assert Polish.price(Decimal.new("1234567.5")) == "1 234 567,50 zł"
  end

  test "whole złoty and numbers" do
    assert Polish.zloty(608) == "608 zł"
    assert Polish.zloty(Decimal.new("1639.5")) == "1 640 zł"
    assert Polish.number(1299) == "1 299"
  end

  test "dates and relative days" do
    assert Polish.date(~D[2026-07-17]) == "17 lipca 2026"
    assert Polish.days_ago(~D[2026-10-30], ~D[2026-10-30]) == "dziś"
    assert Polish.days_ago(~D[2026-10-29], ~D[2026-10-30]) == "wczoraj"
    assert Polish.days_ago(~D[2026-10-27], ~D[2026-10-30]) == "3 dni temu"
  end

  test "plural forms" do
    assert Polish.plural(1, "produkt", "produkty", "produktów") == "1 produkt"
    assert Polish.plural(3, "produkt", "produkty", "produktów") == "3 produkty"
    assert Polish.plural(12, "produkt", "produkty", "produktów") == "12 produktów"
    assert Polish.plural(22, "produkt", "produkty", "produktów") == "22 produkty"
    assert Polish.plural(0, "produkt", "produkty", "produktów") == "0 produktów"
  end
end
