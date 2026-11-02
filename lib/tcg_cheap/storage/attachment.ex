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

  actions do
    action :replace_image, :map do
      transaction? false
      argument :record, :struct, allow_nil?: false
      argument :name, :atom, allow_nil?: false
      argument :body, :binary, allow_nil?: false
      argument :filename, :string, allow_nil?: false
      argument :content_type, :string, allow_nil?: false
      run TcgCheap.Storage.Actions.ReplaceImage
    end

    read :for_owner do
      get? true
      argument :record_type, :string, allow_nil?: false
      argument :record_id, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false

      filter expr(
               record_type == ^arg(:record_type) and record_id == ^arg(:record_id) and
                 name == ^arg(:name)
             )

      prepare build(lock: :for_update, load: [:blob])
    end

    update :replace_blob do
      accept [:blob_id]
    end
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :created_at
  end

  identities do
    identity :record_attachment, [:record_type, :record_id, :name]
  end
end
