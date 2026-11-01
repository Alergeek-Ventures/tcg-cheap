defmodule TcgCheap.Storage.Blob do
  @moduledoc """
  A stored file (an original or one of its WebP variants) in an object
  storage service. Resources attach blobs through an AshStorage attachment
  resource, added with the first resource that stores files.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Storage,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.BlobResource]

  alias TcgCheap.Storage.Changes.PurgeVariants

  postgres do
    table "storage_blobs"
    repo TcgCheap.Repo
  end

  changes do
    change PurgeVariants, on: [:destroy]
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_key, [:key]
    identity :unique_variant, [:variant_of_blob_id, :variant_name, :variant_digest]
  end
end
