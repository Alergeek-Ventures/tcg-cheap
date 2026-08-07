defmodule TcgCheap.Pricing.Singles.Provider do
  @moduledoc """
  Boundary contract implemented by singles listing providers.

  Provider modules are responsible for translating external payloads into
  `TcgCheap.Pricing.Singles.Offer` values. Credentials, retries, and rotation
  remain adapter concerns and are deliberately outside this contract.
  """

  alias TcgCheap.Pricing.Singles.Offer

  @capabilities [
    :condition,
    :destination_shipping,
    :language,
    :price_eur,
    :seller_identity
  ]

  @type card_reference :: map()
  @type capability ::
          :seller_identity
          | :language
          | :condition
          | :destination_shipping
          | :price_eur
          | atom()

  @callback capabilities() :: [capability()]
  @callback fetch_offers(card_reference(), keyword()) ::
              {:ok, [Offer.t()]} | {:error, term()}

  @spec required_capabilities() :: [capability()]
  def required_capabilities, do: @capabilities

  @spec missing_required_capabilities([capability()]) :: [capability()]
  def missing_required_capabilities(capabilities) when is_list(capabilities) do
    @capabilities -- Enum.uniq(capabilities)
  end
end
