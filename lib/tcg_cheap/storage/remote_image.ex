defmodule TcgCheap.Storage.RemoteImage do
  @moduledoc "A canonical image source (TCGdex cards and logos, product contents photos, expansion logos) mirrored into our storage."
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
      accept [:id, :source_url, :trim_margins]
      upsert? true
      upsert_fields [:source_url]
    end

    read :by_hash do
      argument :hash, :string, allow_nil?: false
      get? true
      filter expr(id == ^arg(:hash))
      prepare build(select: [:thumbnail_key, :detail_key, :trim_margins, :attempted_at])
    end

    read :registered do
      argument :hashes, {:array, :string}, allow_nil?: false
      filter expr(id in ^arg(:hashes))
      prepare build(select: [:id, :trim_margins])
    end

    # An image with variants but no attempt is due again (see :trim_margins).
    # A failing source backs off: n failures wait min(2^(n-1), 16) days, so a
    # missing scan is not fetched every day forever. RemoteImageMirror.run/2
    # applies the same rule.
    read :pending do
      argument :limit, :integer, allow_nil?: false
      filter expr(is_nil(thumbnail_key) or is_nil(detail_key) or is_nil(attempted_at))

      # Rows that failed before failures were counted (0) wait a day.
      filter expr(
               is_nil(attempted_at) or
                 fragment(
                   "? < now() AT TIME ZONE 'UTC' - make_interval(days => power(2, least(greatest(? - 1, 0), 4))::integer)",
                   attempted_at,
                   failed_attempts
                 )
             )

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
      change set_attribute(:failed_attempts, 0)
    end

    # Keeps the current keys: a re-mirror that fails still serves the old variants.
    update :record_failure do
      change atomic_update(:failed_attempts, expr(failed_attempts + 1))
      change set_attribute(:attempted_at, &DateTime.utc_now/0)
    end

    # The current variants stay served until the mirror replaces them.
    update :trim_margins do
      change set_attribute(:trim_margins, true)
      change set_attribute(:attempted_at, nil)
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

    attribute :trim_margins, :boolean do
      allow_nil? false
      default false

      description "A logo: the mirror cuts its transparent margins off before making the variants."
    end

    attribute :attempted_at, :utc_datetime_usec

    attribute :failed_attempts, :integer do
      allow_nil? false
      default 0

      description "Consecutive failed mirror attempts; a success resets it. Sets the retry backoff."
    end
  end
end
