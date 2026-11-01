defmodule TcgCheap.Storage.Attachment do
  @moduledoc """
  Links a stored blob to the record it belongs to. Polymorphic (`record_type`
  and `record_id`), so any resource can attach files.
  """

  use Ash.Resource,
    otp_app: :tcg_cheap,
    domain: TcgCheap.Storage,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table "storage_attachments"
    repo TcgCheap.Repo

    custom_indexes do
      index [:record_type, :record_id, :name]
    end
  end

  attachment do
    blob_resource(TcgCheap.Storage.Blob)
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :created_at
  end
end
