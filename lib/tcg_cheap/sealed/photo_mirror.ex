defmodule TcgCheap.Sealed.PhotoMirror do
  @moduledoc """
  Copies product photos from the shops into our object storage, so pages
  serve them as small WebP files from our bucket instead of hotlinking the
  shops' originals (often megabytes each). A product is copied when the photo
  `TcgCheap.Sealed.Refresh` picked from its offers (`image_url`) is new or
  changed. Shops publish the same box at very different sizes, so the
  largest of the product's offer photos is stored, not necessarily the
  picked one, cut to the box when it floats in transparent margins. A
  product whose shop photos are all too poor gets a `checked_photo_url` from
  an admin or agent, which is stored instead. Only image hosts on the
  `TcgCheap.Sealed.ExternalImage` allowlist are fetched.
  """

  require Logger

  alias TcgCheap.{Sealed, Storage}
  alias TcgCheap.Storage.ImageDownload

  @types %{
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/webp" => "webp",
    "image/gif" => "gif"
  }

  # Photos compared per product; one at least as long as the largest variant
  # (960 px) ends the search.
  @max_candidates 5
  @enough_pixels 960

  @doc "Mirrors up to `limit` photos; returns how many were stored and how many failed."
  @spec run(pos_integer(), keyword()) :: %{stored: non_neg_integer(), failed: non_neg_integer()}
  def run(limit, req_options \\ []) do
    products = Sealed.list_photos_to_mirror!(limit)

    offers =
      DateTime.utc_now()
      |> Sealed.current_offers(Enum.map(products, & &1.id),
        select: [:product_id, :price, :in_stock, :image_url]
      )
      |> Enum.group_by(& &1.product_id)

    results = Enum.map(products, &mirror(&1, Map.get(offers, &1.id, []), req_options))
    log_unreadable_hosts(results)

    results
    |> Enum.frequencies_by(fn {outcome, _hosts} -> outcome end)
    |> then(&%{stored: Map.get(&1, :ok, 0), failed: Map.get(&1, :error, 0)})
  end

  # A host whose robots.txt cannot be read fails every one of its photos for the
  # same reason: one line per host and pass, not one per candidate and product.
  defp log_unreadable_hosts(results) do
    results
    |> Enum.flat_map(fn {_outcome, hosts} -> hosts end)
    |> Enum.frequencies()
    |> Enum.each(fn {host, count} ->
      Logger.warning(
        "Photo mirror: robots.txt of #{host} unreadable, #{count} photo candidates skipped"
      )
    end)
  end

  @doc """
  Makes the missing variants (e.g. one added since) of up to `limit` stored
  photos; returns how many photos were completed and how many failed. Pages
  show a variant once stored.
  """
  @spec add_missing_variants(pos_integer()) :: %{
          added: non_neg_integer(),
          failed: non_neg_integer()
        }
  def add_missing_variants(limit) do
    # AshStorage's own URL calculations generate a missing variant.
    limit
    |> Sealed.list_photos_missing_variants!()
    |> Ash.load!([:photo_small_url, :photo_card_url, :photo_page_url])
    |> Enum.frequencies_by(fn product ->
      if product.photo_small_url && product.photo_card_url && product.photo_page_url,
        do: :added,
        else: :failed
    end)
    |> then(&%{added: Map.get(&1, :added, 0), failed: Map.get(&1, :failed, 0)})
  end

  # `{:ok | :error, hosts}`: the hosts whose unreadable robots.txt skipped one
  # of the product's candidates.
  defp mirror(product, offers, req_options) do
    {found, hosts} = largest_photo(candidates(product, offers), req_options)
    {store(product, found), hosts}
  end

  defp store(product, found) do
    with {:ok, body, type} <- found,
         {:ok, body, type} <- ImageDownload.trim_transparent_margins(body, type),
         {:ok, %{blob: blob}} <-
           Storage.replace_image(
             product,
             :photo,
             body,
             "#{product.slug}.#{@types[type]}",
             type
           ),
         blob <- Ash.load!(blob, variants: Ash.Query.select(Storage.Blob, [:variant_name])),
         true <-
           Enum.all?(["small", "card", "page"], fn name ->
             Enum.any?(blob.variants, &(&1.variant_name == name))
           end) do
      Sealed.record_photo_source!(product, source(product))
      :ok
    else
      error ->
        # Already part of the pass's line for the host (`log_unreadable_hosts/1`).
        if error != {:error, :robots_unreadable} do
          Logger.warning(
            "Photo of #{product.slug} not mirrored from #{source(product)}: #{inspect(error)}"
          )
        end

        Sealed.record_photo_attempt!(product)
        :error
    end
  end

  defp source(product), do: product.checked_photo_url || product.image_url

  # A checked photo alone; otherwise the picked photo first, then the other
  # offers' photos, in-stock and cheapest first.
  defp candidates(%{checked_photo_url: url}, _offers) when is_binary(url), do: [url]

  defp candidates(product, offers) do
    others =
      offers
      |> Enum.sort_by(& &1.price, Decimal)
      |> Enum.sort_by(&(not &1.in_stock))
      |> Enum.map(& &1.image_url)

    [product.image_url | others]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(@max_candidates)
  end

  # `{result, hosts}`: the hosts whose robots.txt could not be read are not
  # logged per candidate; `:robots_unreadable` is the result when that skipped
  # every candidate.
  defp largest_photo(urls, req_options) do
    {best, hosts} =
      Enum.reduce_while(urls, {nil, []}, fn url, {best, hosts} ->
        case ImageDownload.fetch(url, req_options) do
          {:ok, body, type} ->
            {action, best} =
              best |> larger({longest_side(body), body, type}) |> halt_when_enough()

            {action, {best, hosts}}

          {:error, {:robots_unreadable, _detail}} ->
            {:cont, {best, [url |> URI.parse() |> Map.fetch!(:host) | hosts]}}

          {:error, reason} ->
            Logger.info("Photo candidate #{url} skipped: #{inspect(reason)}")
            {:cont, {best, hosts}}
        end
      end)

    case {best, hosts} do
      {{_pixels, body, type}, _hosts} -> {{:ok, body, type}, hosts}
      {nil, []} -> {{:error, :no_photo}, hosts}
      {nil, hosts} when length(hosts) == length(urls) -> {{:error, :robots_unreadable}, hosts}
      {nil, _hosts} -> {{:error, :no_photo}, hosts}
    end
  end

  defp halt_when_enough({pixels, _body, _type} = best) when pixels >= @enough_pixels,
    do: {:halt, best}

  defp halt_when_enough(best), do: {:cont, best}

  # Ties keep the earlier, preferred photo.
  defp larger(nil, photo), do: photo

  defp larger({best_pixels, _body, _type} = best, {pixels, _, _}) when best_pixels >= pixels,
    do: best

  defp larger(_best, photo), do: photo

  # ImageDownload has already checked the body decodes.
  defp longest_side(body) do
    {:ok, image} = Image.from_binary(body)
    max(Image.width(image), Image.height(image))
  end
end
