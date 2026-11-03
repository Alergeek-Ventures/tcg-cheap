defmodule TcgCheap.Sealed.ShopFetch do
  @moduledoc """
  Each successful side of a whole-shop fetch, including zero offers. The
  composite shop/kind key gives sealed and singles independent markers and
  rows: a singles rollback cannot advance its marker through a sealed commit.
  """
  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sealed_shop_fetches"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:shop, :kind, :fetched_at]
      upsert? true
      upsert_fields [:fetched_at]
    end
  end

  attributes do
    attribute :shop, :string, primary_key?: true, allow_nil?: false, constraints: [max_length: 40]

    attribute :kind, :atom,
      primary_key?: true,
      allow_nil?: false,
      default: :sealed,
      constraints: [one_of: [:sealed, :single]]

    attribute :fetched_at, :utc_datetime_usec, allow_nil?: false
  end
end
