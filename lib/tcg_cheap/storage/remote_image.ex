defmodule TcgCheap.Storage.RemoteImage do
  @moduledoc "A canonical image source (TCGdex cards and logos, product contents photos) mirrored into our storage."
  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Storage,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage]

  alias TcgCheap.Storage.Variants.ResizedImage

  postgres do
    table "storage_remote_images"
    repo TcgCheap.Repo
  end

  storage do
    blob_resource(TcgCheap.Storage.Blob)
    attachment_resource(TcgCheap.Storage.Attachment)

    has_one_attached :image do
      variant(:thumbnail, {ResizedImage, width: 352}, generate: :eager)
      variant(:detail, {ResizedImage, width: 960}, generate: :eager)
    end
  end

  actions do
    defaults [:read]

    create :register do
      accept [:id, :source_url]
      upsert? true
      upsert_fields [:source_url]
    end

    read :by_hash do
      argument :hash, :string, allow_nil?: false
      get? true
      filter expr(id == ^arg(:hash))
    end

    read :registered do
      argument :hashes, {:array, :string}, allow_nil?: false
      filter expr(id in ^arg(:hashes))
      prepare build(select: [:id])
    end

    read :pending do
      argument :limit, :integer, allow_nil?: false
      filter expr(is_nil(thumbnail_key) or is_nil(detail_key))
      filter expr(is_nil(attempted_at) or attempted_at < ago(1, :day))
      prepare build(sort: [attempted_at: :asc_nils_first, id: :asc], limit: arg(:limit))
    end

    read :mirrored do
      argument :hashes, {:array, :string}, allow_nil?: false
      filter expr(id in ^arg(:hashes) and not is_nil(detail_key))
      prepare build(select: [:id])
    end

    update :record_attempt do
      accept [:thumbnail_key, :detail_key]
      change set_attribute(:attempted_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    attribute :id, :string do
      primary_key? true
      allow_nil? false
      constraints match: ~r/\A[0-9a-f]{64}\z/
    end

    attribute :source_url, :string, allow_nil?: false
    attribute :thumbnail_key, :string
    attribute :detail_key, :string
    attribute :attempted_at, :utc_datetime_usec
  end
end
