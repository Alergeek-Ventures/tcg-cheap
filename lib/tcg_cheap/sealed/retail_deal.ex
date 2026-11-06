defmodule TcgCheap.Sealed.RetailDeal do
  # Days an open-ended deal counts after its first day.
  @open_ended_days 6

  @moduledoc """
  A Pokémon TCG price in a retail chain's shops (Lidl, Rossmann, Żabka…),
  recorded by an agent from the chain's leaflet or a checked deal post:
  chains publish no product feed. It names the catalogue product when it is
  one (a chain's own set may be none), keeps the leaflet's title, and runs
  from `starts_on` to `ends_on`; a deal without an end date (a find in one
  shop) counts for #{@open_ended_days + 1} days. Shown beside the shop offers, never in the
  price verdict: stock differs from shop to shop.

  Every chain has its own logo, with its name in it, in
  `priv/static/images/chains/<chain>.webp`, taken on 2026-11-06: Dino,
  Stokrotka, Hebe, Carrefour, Media Expert, MediaMarkt and Smyk from their
  sites; Biedronka (its site has only a small bitmap) from worldvectorlogo.com;
  the rest from Wikimedia Commons (Auchan's site shows an anniversary
  variant). Netto's site shows only its dog, set here beside the Netto
  wordmark from Commons; the slogans of Biedronka, Dino and Hebe are cut, and
  Media Expert's white lettering made dark for a light chip. Each is
  normalised as the shop logos: fitted into 228×68 on a 240×80 white chip
  (Pepco's and Stokrotka's filled tiles into 200×56). A new chain needs one.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  alias TcgCheap.Sealed.Validations.HttpsUrls

  @chains [
    lidl: "Lidl",
    biedronka: "Biedronka",
    kaufland: "Kaufland",
    aldi: "Aldi",
    netto: "Netto",
    dino: "Dino",
    zabka: "Żabka",
    stokrotka: "Stokrotka",
    auchan: "Auchan",
    carrefour: "Carrefour",
    rossmann: "Rossmann",
    hebe: "Hebe",
    pepco: "Pepco",
    action: "Action",
    tedi: "TEDi",
    kik: "KiK",
    smyk: "Smyk",
    empik: "Empik",
    media_expert: "Media Expert",
    media_markt: "MediaMarkt"
  ]

  postgres do
    table "sealed_retail_deals"
    repo TcgCheap.Repo

    references do
      reference :product, on_delete: :nilify
    end

    custom_indexes do
      index [:product_id]
      index [:starts_on]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      description """
      Records a chain's price from its leaflet or a checked deal post. Give the exact catalogue
      product (search_products) only when the leaflet names it; otherwise leave product_id null.
      Never guess an end date: leave ends_on null for a find without one (it then shows for
      #{@open_ended_days + 1} days).
      """

      accept [
        :chain,
        :product_id,
        :title,
        :price,
        :starts_on,
        :ends_on,
        :source_url,
        :note
      ]
    end

    read :current do
      description "Deals running on the given day, the cheapest first."
      argument :today, :date, allow_nil?: false

      filter expr(
               starts_on <= ^arg(:today) and
                 (ends_on >= ^arg(:today) or
                    (is_nil(ends_on) and
                       date_add(starts_on, @open_ended_days, :day) >= ^arg(:today)))
             )

      prepare build(sort: [price: :asc, starts_on: :desc, id: :asc], load: [:product])
    end
  end

  validations do
    validate compare(:price, greater_than: 0)

    validate compare(:ends_on, greater_than_or_equal_to: :starts_on) do
      where present(:ends_on)
    end

    validate {HttpsUrls, attribute: :source_url}
  end

  attributes do
    uuid_primary_key :id

    attribute :chain, :atom do
      allow_nil? false
      public? true
      constraints one_of: Keyword.keys(@chains)
    end

    attribute :title, :string do
      description "The product as the leaflet or post names it, on one line."
      allow_nil? false
      public? true
      constraints max_length: 300, match: ~r/\A[^\r\n]*\z/
    end

    attribute :price, :decimal do
      description "The price in PLN, gross."
      allow_nil? false
      public? true
    end

    attribute :starts_on, :date do
      allow_nil? false
      public? true
    end

    attribute :ends_on, :date do
      description "The last day; null when the source gives none."
      public? true
    end

    attribute :source_url, :string do
      description "The https leaflet or deal post the price comes from."
      allow_nil? false
      public? true
      constraints max_length: 2_000
    end

    attribute :note, :string do
      description ~s(A short caveat in Polish, e.g. "wybrane sklepy" or "woj. dolnośląskie".)
      public? true
      constraints max_length: 200, match: ~r/\A[^\r\n]*\z/
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :product, TcgCheap.Sealed.Product do
      public? true
    end
  end

  @doc "The chain keys an agent may record."
  def chains, do: Keyword.keys(@chains)

  @doc "Whether the chain's logo is a square mark, cut to its middle on a phone."
  def square_logo?(chain), do: chain in [:lidl, :aldi, :kik, :tedi]

  @doc "A chain's name as shoppers know it."
  def chain_name(chain), do: Keyword.fetch!(@chains, chain)
end
