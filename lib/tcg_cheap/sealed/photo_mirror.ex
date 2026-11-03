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
  `TcgCheap.Catalogue.ExternalImage` allowlist are fetched.
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

    products
    |> Enum.map(&mirror(&1, Map.get(offers, &1.id, []), req_options))
    |> Enum.frequencies()
    |> then(&%{stored: Map.get(&1, :ok, 0), failed: Map.get(&1, :error, 0)})
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

  defp mirror(product, offers, req_options) do
    with {:ok, body, type} <- largest_photo(candidates(product, offers), req_options),
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
        Logger.warning(
          "Photo of #{product.slug} not mirrored from #{source(product)}: #{inspect(error)}"
        )

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

  defp largest_photo(urls, req_options) do
    urls
    |> Enum.reduce_while(nil, fn url, best ->
      case ImageDownload.fetch(url, req_options) do
        {:ok, body, type} ->
          best |> larger({longest_side(body), body, type}) |> halt_when_enough()

        {:error, reason} ->
          Logger.info("Photo candidate #{url} skipped: #{inspect(reason)}")
          {:cont, best}
      end
    end)
    |> case do
      {_pixels, body, type} -> {:ok, body, type}
      nil -> {:error, :no_photo}
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
