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
end
