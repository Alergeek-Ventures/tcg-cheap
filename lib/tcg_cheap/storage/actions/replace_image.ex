defmodule TcgCheap.Storage.Actions.ReplaceImage do
  @moduledoc "Stages complete image variants before atomically switching the attachment."
  use Ash.Resource.Actions.Implementation

  require Logger

  alias AshStorage.Service.Context
  alias TcgCheap.{Repo, Storage}

  @impl true
  def run(input, _opts, _context) do
    if Repo.in_transaction?(),
      do: {:error, "Image replacement must run outside an existing transaction"},
      else: replace(input.arguments)
  end

  defp replace(%{record: record, name: name, body: body, filename: filename, content_type: type}) do
    resource = record.__struct__

    with {:ok, definition} <- AshStorage.Info.attachment(resource, name),
         {:ok, {service, opts}} <- AshStorage.Info.service_for_attachment(resource, definition),
         {:ok, blob} <- create_blob(body, filename, type, service, opts) do
      stage_and_swap(record, name, body, blob, definition, service, opts)
    end
  end

  defp stage_and_swap(record, name, body, blob, definition, service, opts) do
    resource = record.__struct__

    ctx =
      opts
      |> Context.new(resource: resource, attachment: definition)
      |> Context.put_expected_md5(blob.checksum)
      |> Context.put_blob_metadata(content_type: blob.content_type, filename: blob.filename)

    result =
      with :ok <- service.upload(blob.key, body, ctx),
           :ok <- generate_variants(blob, definition, resource) do
        swap(record, name, blob)
      end

    finish(result, blob)
  end

  defp finish({:ok, %{old_blob: old_blob} = attached}, _staged_blob) do
    if old_blob, do: cleanup(old_blob)
    {:ok, Map.delete(attached, :old_blob)}
  end

  defp finish({:error, _reason} = error, staged_blob) do
    cleanup(staged_blob)
    error
  end

  defp create_blob(body, filename, type, service, opts) do
    Storage.create_blob(%{
      key: AshStorage.generate_key(),
      filename: filename,
      content_type: type,
      byte_size: byte_size(body),
      checksum: checksum(body),
      service_name: service,
      service_opts: opts |> Keyword.take(Keyword.keys(service.service_opts_fields())) |> Map.new()
    })
  end

  # S3's Content-MD5 is a transport integrity checksum, not an authentication hash.
  # sobelow_skip ["Crypto.WeakHash"]
  defp checksum(body), do: :crypto.hash(:md5, body) |> Base.encode64()

  defp generate_variants(blob, definition, resource) do
    Enum.reduce_while(definition.variants, :ok, fn variant, :ok ->
      case AshStorage.VariantGenerator.generate(blob, variant, resource, definition) do
        {:ok, _variant} -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # Only the pointer changes inside this transaction. Object deletion must not
  # happen until it commits: SQL rollback cannot restore deleted S3 files.
  defp swap(record, name, blob) do
    record_type = to_string(record.__struct__)
    record_id = to_string(record.id)
    name = to_string(name)

    Repo.transaction(fn ->
      with {:ok, existing} <- Storage.get_image_attachment(record_type, record_id, name),
           {:ok, attachment} <- set_blob(existing, record_type, record_id, name, blob.id) do
        %{blob: blob, attachment: attachment, old_blob: existing && existing.blob}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp set_blob(nil, record_type, record_id, name, blob_id) do
    Storage.create_image_attachment(%{
      record_type: record_type,
      record_id: record_id,
      name: name,
      blob_id: blob_id
    })
  end

  defp set_blob(existing, _record_type, _record_id, _name, blob_id),
    do: Storage.replace_attachment_blob(existing, blob_id)

  defp cleanup(blob) do
    case Storage.purge_blob(blob) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Image blob #{blob.id} cleanup failed: #{inspect(reason)}")
    end
  end
end
