defmodule TcgCheap.Storage.RemoteImageMirror do
  @moduledoc "Registers known database sources and mirrors them in bounded background batches."

  require Logger
  import Ecto.Query

  alias TcgCheap.Repo
  alias TcgCheap.Sealed.{CardGuide, CardImage, TcgdexCard, TcgdexSet}
  alias TcgCheap.Storage

  # Fixed by `CardImage.classic_collection/0`, never by a request.
  @classic_collection_values Enum.map_join(CardImage.classic_collection(), ", ", fn {number, code} ->
                               "('#{number}', '#{code}')"
                             end)

  # Keyset scan across the known source columns. No request parameter can add a
  # source, and neither rendering nor the media controller invokes this query.
  @sources """
  SELECT url, kind FROM (
    SELECT logo_url AS url, 'logo' AS kind FROM sealed_tcgdex_sets
    UNION
    SELECT s.card_images_url || '/' || c.number, 'card' AS kind
      FROM sealed_tcgdex_cards c
      JOIN sealed_tcgdex_sets s ON c.tcgdex_set_id = s.id
      WHERE s.language = 'en' AND s.cards_source_url IS NULL
        AND s.card_images_url IS NOT NULL
    UNION
    SELECT 'https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/' || s.abbreviation || '/'
             || s.abbreviation || '_'
             || CASE WHEN c.number ~ '^[A-Z]$' THEN c.number
                ELSE lpad(c.number, greatest(3, length(c.number)), '0') END
             || '_R_EN_LG.png',
           'card' AS kind
      FROM sealed_tcgdex_cards c
      JOIN sealed_tcgdex_sets s ON c.tcgdex_set_id = s.id
      WHERE s.language = 'en'
        AND s.abbreviation ~ '^[A-Z0-9]+$' AND c.number ~ '^([0-9]+|[A-Z])$'
        -- 30C_001 is 30th Celebration's card; the collection's scans follow below.
        AND s.tcgdex_id <> '30th-c'
        -- Only where TCGdex has no image: no directory, or the card's failed to download.
        AND (s.card_images_url IS NULL OR EXISTS (
          SELECT 1 FROM storage_remote_images r
           WHERE r.id = encode(sha256(convert_to(s.card_images_url || '/' || c.number || '/high.webp', 'UTF8')), 'hex')
             AND r.attempted_at IS NOT NULL AND r.detail_key IS NULL))
    UNION
    SELECT 'https://images.pokemontcg.io/' || s.tcgdex_id || '/'
             || CASE WHEN s.tcgdex_id = 'svp' THEN ltrim(c.number, '0') ELSE c.number END
             || '_hires.png', 'card' AS kind
      FROM sealed_tcgdex_cards c
      JOIN sealed_tcgdex_sets s ON c.tcgdex_set_id = s.id
      WHERE s.language = 'en'
        AND ((s.tcgdex_id = 'swshp' AND c.number ~ '^SWSH[0-9]{3}$')
          OR (s.tcgdex_id = 'svp' AND c.number ~ '^[0-9]{3}$' AND c.number <> '000'))
        -- Promos TCGdex has no image of, as for Limitless above.
        AND (s.card_images_url IS NULL OR EXISTS (
          SELECT 1 FROM storage_remote_images r
           WHERE r.id = encode(sha256(convert_to(s.card_images_url || '/' || c.number || '/high.webp', 'UTF8')), 'hex')
             AND r.attempted_at IS NOT NULL AND r.detail_key IS NULL))
    UNION
    SELECT 'https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/30C/30C_' || m.code || '_R_EN_LG.png',
           'card' AS kind
      FROM sealed_tcgdex_cards c
      JOIN sealed_tcgdex_sets s ON c.tcgdex_set_id = s.id
      JOIN (VALUES #{@classic_collection_values}) AS m(number, code) ON m.number = c.number
      WHERE s.language = 'en' AND s.tcgdex_id = '30th-c'
    UNION
    SELECT 'https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/CRZ/CRZ_GG'
             || ltrim(substring(c.number FROM 3), '0') || '_R_EN_LG.png', 'card' AS kind
      FROM sealed_tcgdex_cards c
      JOIN sealed_tcgdex_sets s ON c.tcgdex_set_id = s.id
      WHERE s.language = 'en' AND s.cards_source_url IS NULL
        AND s.abbreviation = 'CRZ:GG' AND c.number ~ '^GG[0-9]{2}$'
    UNION
    SELECT item->>'image' AS url, 'card' AS kind
      FROM sealed_products,
           jsonb_array_elements(COALESCE(contents->'items', '[]'::jsonb)) AS item
    UNION
    SELECT source.url, source.kind
      FROM sealed_products,
           jsonb_array_elements(COALESCE(contents->'items', '[]'::jsonb)) AS item,
           jsonb_array_elements(
             CASE jsonb_typeof(item->'cards') WHEN 'array' THEN item->'cards' ELSE '[]'::jsonb END
           ) AS card,
           LATERAL (VALUES (card->>'image', 'card'), (card->>'photo', 'photo')) AS source(url, kind)
    UNION
    SELECT source.url, source.kind
      FROM sealed_products,
           jsonb_array_elements(COALESCE(contents->'items', '[]'::jsonb)) AS item,
           jsonb_array_elements(
             CASE jsonb_typeof(item->'variants') WHEN 'array' THEN item->'variants' ELSE '[]'::jsonb END
           ) AS variant,
           jsonb_array_elements(
             CASE jsonb_typeof(variant->'cards') WHEN 'array' THEN variant->'cards' ELSE '[]'::jsonb END
           ) AS card,
           LATERAL (VALUES (card->>'image', 'card'), (card->>'photo', 'photo')) AS source(url, kind)
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

  @logo_kinds ["logo", "expansion_logo"]

  # Hosts of the card scans and set logos the mirror derives itself
  # (`CardImage`), many of which do not exist. A missing image elsewhere was
  # chosen by hand (product photos, expansion logos), so it stays a warning.
  @scan_hosts [
    "assets.tcgdex.net",
    "images.pokemontcg.io",
    "limitlesstcg.nyc3.cdn.digitaloceanspaces.com"
  ]

  # Limitless's object storage answers 403, not 404, for a scan it does not
  # have; elsewhere a 403 is a block (hotlinking, bots) and stays a warning.
  @missing_as_403 ["limitlesstcg.nyc3.cdn.digitaloceanspaces.com"]

  # A run that mirrors nothing while this many images fail on their first
  # attempt looks like a source outage rather than missing scans.
  @outage_first_failures 10

  @doc "Registers a page of known URLs; returns its keyset cursor and row count."
  @spec register_batch([String.t()], pos_integer()) :: {[String.t()], non_neg_integer()}
  def register_batch([url, kind] = cursor, limit) do
    %{rows: rows} = TcgCheap.Repo.query!(@sources, [url, kind, limit])

    # A source used as a logo anywhere is trimmed.
    sources =
      for [url, kind] <- rows, source = canonical_source(url, kind), reduce: %{} do
        sources ->
          trim? = kind in @logo_kinds

          Map.update(sources, CardImage.source_hash(source), {source, trim?}, fn {source, other} ->
            {source, trim? or other}
          end)
      end

    registered =
      sources
      |> Map.keys()
      |> Storage.list_registered_remote_images!()
      |> Map.new(&{&1.id, &1})

    # Logos mirrored before they were trimmed are mirrored again.
    for {hash, {source, trim?}} <- sources do
      case registered[hash] do
        nil ->
          Storage.register_remote_image!(%{id: hash, source_url: source, trim_margins: trim?})

        %{trim_margins: false} = image when trim? ->
          Storage.trim_remote_image_margins!(image)

        _image ->
          :ok
      end
    end

    {List.last(rows) || cursor, length(rows)}
  end

  @doc """
  Mirrors due images and returns how many were attempted. A failing source
  backs off (1, 2, 4, then every 8 days) while fresh images continue.
  """
  @spec run(pos_integer(), keyword()) :: non_neg_integer()
  def run(limit, req_options \\ []) do
    # Register offered cards before the catalogue keyset scan reaches them.
    # The same priority is applied when selecting due work, including resumed jobs.
    sources = offered_sources()

    from(s in subquery(sources),
      left_join: image in Storage.RemoteImage,
      on: image.source_url == s.source_url,
      where: is_nil(image.id),
      order_by: s.source_url,
      limit: ^limit,
      select: s.source_url
    )
    |> Repo.all()
    |> Enum.each(fn url ->
      if source = canonical_source(url, "card") do
        Storage.register_remote_image!(%{id: CardImage.source_hash(source), source_url: source})
      end
    end)

    images =
      from(image in Storage.RemoteImage,
        left_join: s in subquery(sources),
        on: image.source_url == s.source_url,
        where:
          is_nil(image.thumbnail_key) or is_nil(image.detail_key) or is_nil(image.attempted_at),
        # The :pending read action's backoff: n failures wait min(2^(n-1), 8)
        # days; rows that failed before failures were counted wait a day.
        where:
          is_nil(image.attempted_at) or
            fragment(
              "? < now() AT TIME ZONE 'UTC' - make_interval(days => power(2, least(greatest(? - 1, 0), 3))::integer)",
              image.attempted_at,
              image.failed_attempts
            ),
        order_by: [
          desc: not is_nil(s.source_url),
          asc_nulls_first: image.attempted_at,
          asc: image.id
        ],
        limit: ^limit,
        select: image
      )
      |> Repo.all()

    images |> Enum.map(&mirror(&1, req_options)) |> log_summary()
    length(images)
  end

  defp log_summary([]), do: :ok

  # Info normally; a warning when nothing was mirrored and many images failed on
  # their first attempt, which a source outage looks like (already mirrored
  # images are never fetched again, so only new ones show it).
  defp log_summary(results) do
    {mirrored, failures} = Enum.split_with(results, &(&1 == :mirrored))
    first_failures = Enum.count(failures, fn {:failed, _reason, first?} -> first? end)

    reasons =
      failures
      |> Enum.frequencies_by(fn {:failed, reason, _first?} -> reason end)
      |> Enum.sort_by(fn {reason, count} -> {reason == "other", -count, reason} end)
      |> Enum.map_join(", ", fn {reason, count} -> "#{reason}: #{count}" end)

    summary =
      "Remote images: #{length(mirrored)} mirrored, #{length(failures)} failed, " <>
        "#{first_failures} on their first attempt"

    level =
      if mirrored == [] and first_failures >= @outage_first_failures, do: :warning, else: :info

    Logger.log(level, if(reasons == "", do: summary, else: "#{summary} (#{reasons})"))
  end

  # All current offers count, including out-of-stock cards people search for.
  # Source construction matches CardImage.single_sources/2, except
  # pokemontcg.io's promo scans, which only the keyset scan registers; no
  # remote I/O.
  defp offered_sources do
    from(c in TcgdexCard,
      join: s in TcgdexSet,
      on: c.tcgdex_set_id == s.id,
      join: o in subquery(CardGuide.current_query()),
      on: o.card_id == c.id,
      where: is_nil(o.grading) and s.language == "en",
      # Not 30C_001 (30th Celebration's) for the collection; @sources has its scans.
      where: not is_nil(s.card_images_url) or s.tcgdex_id != "30th-c",
      where:
        not is_nil(s.card_images_url) or
          (fragment("? ~ '^[A-Z0-9]+$'", s.abbreviation) and fragment("? ~ '^[0-9]+$'", c.number)) or
          (s.abbreviation == "CRZ:GG" and fragment("? ~ '^GG[0-9]{2}$'", c.number)),
      distinct: true,
      select: %{
        source_url:
          fragment(
            """
            CASE WHEN ? IS NOT NULL THEN ? || '/' || ? || '/high.webp'
            WHEN ? = 'CRZ:GG' AND ? ~ '^GG[0-9]{2}$'
            THEN 'https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/CRZ/CRZ_GG'
                 || ltrim(substring(? FROM 3), '0') || '_R_EN_LG.png'
            ELSE 'https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/' || ? || '/' || ? || '_'
                 || lpad(?, greatest(3, length(?)), '0') || '_R_EN_LG.png' END
            """,
            s.card_images_url,
            s.card_images_url,
            c.number,
            s.abbreviation,
            c.number,
            c.number,
            s.abbreviation,
            s.abbreviation,
            c.number,
            c.number
          )
      }
    )
  end

  # A cropped photo is cut out of its picture, then cut to the item if the
  # picture is transparent around it.
  defp mirror(image, req_options) do
    {source, crop} = Storage.ImageDownload.split_crop(image.source_url)

    with {:ok, body, type} <- Storage.ImageDownload.fetch(source, req_options),
         {:ok, body, type} <- Storage.ImageDownload.crop(body, type, crop),
         {:ok, body, type} <- trim_margins(body, type, image.trim_margins or crop != nil),
         {:ok, %{blob: blob}} <-
           Storage.replace_image(
             image,
             :image,
             body,
             "#{image.id}.#{extension(type)}",
             type
           ),
         blob <- Ash.load!(blob, variants: Ash.Query.select(Storage.Blob, [:key, :variant_name])),
         %{} = thumbnail <- Enum.find(blob.variants, &(&1.variant_name == "thumbnail")),
         %{} = detail <- Enum.find(blob.variants, &(&1.variant_name == "detail")) do
      Storage.record_remote_image_attempt!(image, %{
        thumbnail_key: thumbnail.key,
        detail_key: detail.key
      })

      :mirrored
    else
      error ->
        Storage.record_remote_image_failure!(image)
        {:failed, log_failure(error, image), is_nil(image.attempted_at)}
    end
  end

  # A missing card scan or set logo (a 404 from a scan host, or Limitless's
  # 403) is remembered by the backoff and counted per host in the run's
  # summary. Any other failure needs a look, so it is logged on its own.
  defp log_failure({:error, {:http_status, status}} = error, image) when status in [403, 404] do
    host = URI.parse(image.source_url).host

    if (status == 404 and host in @scan_hosts) or (status == 403 and host in @missing_as_403) do
      Logger.debug("Remote image source missing: http #{status} (#{image.id})")
      "http #{status} #{host}"
    else
      log_unexpected_failure(error, image)
    end
  end

  defp log_failure(error, image), do: log_unexpected_failure(error, image)

  defp log_unexpected_failure(error, image) do
    Logger.warning("Remote image mirror failed: #{inspect(failure_reason(error))} (#{image.id})")
    "other"
  end

  defp failure_reason({:error, reason}), do: reason
  defp failure_reason(nil), do: :missing_variant
  # Any other shape (e.g. a replace_image result without a blob) is logged as is.
  defp failure_reason(other), do: other

  # Logos are trimmed so they show as large as a tight logo on the expansion tiles.
  defp trim_margins(body, type, false), do: {:ok, body, type}

  defp trim_margins(body, type, true),
    do: Storage.ImageDownload.trim_transparent_margins(body, type)

  defp canonical_source(url, "card"), do: CardImage.card_source_url(url)
  defp canonical_source(url, "logo"), do: CardImage.logo_source_url(url)
  defp canonical_source(url, "photo"), do: CardImage.photo_source_url(url)
  defp canonical_source(url, "expansion_logo"), do: CardImage.expansion_logo_source_url(url)

  defp extension("image/jpeg"), do: "jpg"
  defp extension("image/png"), do: "png"
  defp extension("image/webp"), do: "webp"
  defp extension("image/gif"), do: "gif"
end
