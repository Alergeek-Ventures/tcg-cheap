defmodule TcgCheap.Storage.RemoteImageMirror do
  @moduledoc "Registers known database sources and mirrors them in bounded background batches."

  require Logger

  alias TcgCheap.Catalogue.CardImage
  alias TcgCheap.Storage

  # Keyset scan across the known source columns. No request parameter can add a
  # source, and neither rendering nor the media controller invokes this query.
  @sources """
  SELECT url, kind FROM (
    SELECT image_url AS url, 'card' AS kind FROM card_printings
    UNION
    SELECT logo_url AS url, 'logo' AS kind FROM card_sets
    UNION
    SELECT logo_url AS url, 'logo' AS kind FROM sealed_tcgdex_sets
    UNION
    SELECT item->>'image' AS url, 'card' AS kind
      FROM sealed_products,
           jsonb_array_elements(COALESCE(contents->'items', '[]'::jsonb)) AS item
    UNION
    SELECT item->>'photo' AS url, 'photo' AS kind
      FROM sealed_products,
           jsonb_array_elements(COALESCE(contents->'items', '[]'::jsonb)) AS item
    UNION
    SELECT url, 'expansion_logo' AS kind FROM sealed_expansion_logos
  ) AS sources
  WHERE url IS NOT NULL AND url <> '' AND (url, kind) > ($1, $2)
  ORDER BY url, kind LIMIT $3
  """

  @doc "Registers a page of known URLs; returns its keyset cursor and row count."
  @spec register_batch([String.t()], pos_integer()) :: {[String.t()], non_neg_integer()}
  def register_batch([url, kind] = cursor, limit) do
    %{rows: rows} = TcgCheap.Repo.query!(@sources, [url, kind, limit])

    sources =
      rows
      |> Enum.map(fn [url, kind] -> canonical_source(url, kind) end)
      |> Enum.reject(&is_nil/1)
      |> Map.new(&{CardImage.source_hash(&1), &1})

    registered =
      sources
      |> Map.keys()
      |> Storage.list_registered_remote_images!()
      |> MapSet.new(& &1.id)

    for {hash, source} <- sources, not MapSet.member?(registered, hash) do
      Storage.register_remote_image!(%{id: hash, source_url: source})
    end

    {List.last(rows) || cursor, length(rows)}
  end

  @doc "Mirrors due images; failures wait a day while fresh images continue."
  @spec run(pos_integer(), keyword()) :: non_neg_integer()
  def run(limit, req_options \\ []) do
    images = Storage.list_pending_remote_images!(limit)
    Enum.each(images, &mirror(&1, req_options))
    length(images)
  end

  defp mirror(image, req_options) do
    with {:ok, body, type} <- Storage.ImageDownload.fetch(image.source_url, req_options),
         {:ok, %{blob: blob}} <-
           Storage.replace_image(
             image,
             :image,
             body,
             "#{image.id}.#{extension(type)}",
             type
           ),
         blob <- Ash.load!(blob, :variants),
         %{} = thumbnail <- Enum.find(blob.variants, &(&1.variant_name == "thumbnail")),
         %{} = detail <- Enum.find(blob.variants, &(&1.variant_name == "detail")) do
      Storage.record_remote_image_attempt!(image, %{
        thumbnail_key: thumbnail.key,
        detail_key: detail.key
      })
    else
      error ->
        Logger.warning("Remote image #{image.id} mirror failed: #{inspect(error)}")
        Storage.record_remote_image_attempt!(image, %{})
    end
  end

  defp canonical_source(url, "card"), do: CardImage.source_url(url)
  defp canonical_source(url, "logo"), do: CardImage.logo_source_url(url)
  defp canonical_source(url, "photo"), do: CardImage.photo_source_url(url)
  defp canonical_source(url, "expansion_logo"), do: CardImage.expansion_logo_source_url(url)

  defp extension("image/jpeg"), do: "jpg"
  defp extension("image/png"), do: "png"
  defp extension("image/webp"), do: "webp"
  defp extension("image/gif"), do: "gif"
end
