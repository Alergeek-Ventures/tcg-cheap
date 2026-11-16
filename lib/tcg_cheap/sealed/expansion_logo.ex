defmodule TcgCheap.Sealed.ExpansionLogo do
  @moduledoc """
  The logo an agent or admin found for a Cardmarket expansion that TCGdex
  gives none for (Japanese and other editions, promos), with the https page
  it came from and the day it was checked. The image must be on a host we
  mirror from (`TcgCheap.Sealed.ExternalImage`); the guide shows it only
  once it is mirrored, and a mirrored English TCGdex logo wins over it.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Sealed,
    data_layer: AshPostgres.DataLayer

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Cache, CardImage, TcgdexSet}
  alias TcgCheap.Sealed.Validations.{HttpsUrls, ImageHost}

  postgres do
    table "sealed_expansion_logos"
    repo TcgCheap.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :set do
      accept [:cardmarket_expansion_id, :url, :page, :checked_on]
      upsert? true
      upsert_fields [:url, :page, :checked_on, :updated_at]
    end
  end

  validations do
    validate {ImageHost, attribute: :url}
    validate {HttpsUrls, attribute: :page}
  end

  attributes do
    attribute :cardmarket_expansion_id, :integer do
      primary_key? true
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :url, :string do
      description "The logo image, on an allowlisted image host."
      allow_nil? false
      public? true
      constraints max_length: 2_000
    end

    attribute :page, :string do
      description "The https page the logo was found on."
      allow_nil? false
      public? true
      constraints max_length: 2_000
    end

    attribute :checked_on, :date do
      description "The day the logo was checked against the expansion."
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  @doc "The expansions' mirrored logos by Cardmarket expansion id."
  @spec mirrored_urls() :: %{integer() => String.t()}
  def mirrored_urls do
    # Cache sources, not object keys: replacing a mirrored image deletes the
    # previous objects, so each render resolves the currently stored variants.
    # Logos show at most ~5.5rem tall, mostly as ~2rem expansion filter tiles:
    # the thumbnail is sharp there, and half the bytes of a large logo's detail.
    sources = Cache.fetch(:logo_sources, &read_sources/0)

    mirrored =
      sources
      |> Enum.map(&CardImage.source_hash(elem(&1, 1)))
      |> TcgCheap.Storage.mirrored_image_urls(:thumbnail)

    # TCGdex last, so its mirrored logo replaces a set one.
    for {id, source} <- sources,
        url = Map.get(mirrored, CardImage.source_hash(source)),
        into: %{},
        do: {id, url}
  end

  # Per expansion, the mirrored English TCGdex logo, else the mirrored logo
  # set for it (any edition). Only mirrored images are shown, so a tile never
  # shows a broken image.
  defp read_sources do
    tcgdex =
      for {id, %{language: "en", logo_url: "" <> url}} <-
            TcgdexSet.by_expansion(
              Sealed.list_tcgdex_sets!(
                query: [select: [:cardmarket_expansion_id, :language, :name, :logo_url]]
              )
            ),
          source = CardImage.logo_source_url(url),
          do: {id, source}

    set =
      for logo <- Sealed.list_expansion_logos!(),
          source = CardImage.expansion_logo_source_url(logo.url),
          do: {logo.cardmarket_expansion_id, source}

    set ++ tcgdex
  end
end
