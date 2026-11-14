defmodule TcgCheap.Repo.Migrations.BackfillOfferShopPrices do
  @moduledoc """
  Fills the shop's own price of every offer from a shop pricing in PLN, whose
  stored price already is it. The shops abroad (in another currency on
  2026-11-14, listed here) fill theirs on their next fetch; until then their
  offers count in Polish prices only.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE sealed_offers SET shop_price = price, currency = 'PLN'
    WHERE shop_price IS NULL
      AND shop NOT IN ('bangerpack', 'rarecards', 'tcgking', 'gemipulls',
                       'pokemagic', 'chasedex', 'unicorncards', 'bulbazard')
    """)

    execute("""
    UPDATE sealed_card_offers SET shop_price = price, currency = 'PLN'
    WHERE shop_price IS NULL
      AND shop NOT IN ('bangerpack', 'rarecards', 'tcgking', 'gemipulls',
                       'pokemagic', 'chasedex', 'unicorncards', 'bulbazard')
    """)
  end

  # The columns go with the migration that added them.
  def down, do: :ok
end
