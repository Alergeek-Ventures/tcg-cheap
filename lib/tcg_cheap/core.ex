defmodule TcgCheap.Core do
  @moduledoc """
  The catalogue and pricing resources that back public, locally cached data.
  """

  use Ash.Domain,
    otp_app: :tcg_cheap

  resources do
    resource TcgCheap.Catalogue.CardSet do
      define :import_card_set, action: :import
      define :get_card_set_by_tcgdex_id, action: :by_tcgdex_id, args: [:tcgdex_id]
    end

    resource TcgCheap.Catalogue.CardPrinting do
      define :create_card_printing, action: :create
      define :import_card_printing, action: :import
      define :seed_card_printing_brief, action: :seed_brief
      define :get_card_printing_by_tcgdex_id, action: :by_tcgdex_id, args: [:tcgdex_id]

      define :search_card_printings,
        action: :search,
        args: [:query, {:optional, :limit}]

      define :lock_card_printing_for_update, action: :lock_for_update_by_id, args: [:id]

      define :lock_card_printing_for_update_by_tcgdex_id,
        action: :lock_for_update_by_tcgdex_id,
        args: [:tcgdex_id],
        not_found_error?: false
    end

    resource TcgCheap.Pricing.Singles.SingleValuationSnapshot do
      define :record_single_valuation, action: :record
      define :archive_single_valuation, action: :archive
      define :list_current_single_valuations, action: :current_for_card, args: [:card_printing_id]

      define :get_current_single_valuation,
        action: :current_for_card_and_policy,
        args: [:card_printing_id, :policy_version],
        not_found_error?: false

      define :list_single_valuation_history,
        action: :history_for_card_and_policy,
        args: [:card_printing_id, :policy_version]

      define :list_single_valuation_history_since,
        action: :history_since_for_card_and_policy,
        args: [:card_printing_id, :policy_version, :since]
    end
  end
end
