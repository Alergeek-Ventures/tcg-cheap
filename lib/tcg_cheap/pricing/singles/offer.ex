defmodule TcgCheap.Pricing.Singles.Offer do
  @moduledoc """
  Provider-neutral representation of one singles listing.

  Provider adapters must translate their payloads into this struct before a
  valuation is performed. In particular, `seller_key` is the stable provider
  identity used to deduplicate listings from the same seller.
  """

  @enforce_keys [:seller_key, :language, :condition, :ships_to_poland?, :price_eur]
  defstruct [
    :seller_key,
    :language,
    :condition,
    :ships_to_poland?,
    :price_eur,
    :source_listing_id,
    :seller_country,
    :quantity,
    :observed_at
  ]

  @type language ::
          :en
          | :de
          | :fr
          | :it
          | :es
          | :pt
          | :ja
          | :ko
          | :zh_s
          | :zh_t
          | :ru
          | :nl
          | :pl

  @type condition ::
          :mint
          | :near_mint
          | :excellent
          | :good
          | :light_played
          | :moderately_played
          | :heavily_played
          | :played
          | :poor
  @type seller_key :: binary()
  @type t :: %__MODULE__{
          seller_key: seller_key(),
          language: language(),
          condition: condition(),
          ships_to_poland?: boolean(),
          price_eur: Decimal.t(),
          source_listing_id: binary() | nil,
          seller_country: binary() | nil,
          quantity: pos_integer() | nil,
          observed_at: DateTime.t() | nil
        }
end
