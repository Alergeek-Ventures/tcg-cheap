defmodule TcgCheap.Sealed.PhotoMirror do
  @moduledoc """
  Copies product photos from the shops into our object storage, so pages
  serve them as small WebP files from our bucket instead of hotlinking the
  shops' originals (often megabytes each). A product's photo is the one
  `TcgCheap.Sealed.Refresh` picked from its offers (`image_url`); it is copied
  again when that choice changes. Only image hosts on the
  `TcgCheap.Catalogue.ExternalImage` allowlist are fetched.
  """

  require Logger

  alias TcgCheap.Sealed
  alias TcgCheap.Storage.ImageDownload

  @types %{
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/webp" => "webp",
    "image/gif" => "gif"
  }

  @doc "Mirrors up to `limit` photos; returns how many were stored and how many failed."
  @spec run(pos_integer(), keyword()) :: %{stored: non_neg_integer(), failed: non_neg_integer()}
  def run(limit, req_options \\ []) do
    limit
    |> Sealed.list_photos_to_mirror!()
    |> Enum.map(&mirror(&1, req_options))
    |> Enum.frequencies()
    |> then(&%{stored: Map.get(&1, :ok, 0), failed: Map.get(&1, :error, 0)})
  end

  defp mirror(product, req_options) do
    url = product.image_url

    with {:ok, body, type} <- ImageDownload.fetch(url, req_options),
         {:ok, %{blob: blob}} <-
           AshStorage.Operations.attach(product, :photo, body,
             filename: "#{product.slug}.#{@types[type]}",
             content_type: type
           ),
         blob <- Ash.load!(blob, :variants),
         true <-
           Enum.all?(["card", "page"], fn name ->
             Enum.any?(blob.variants, &(&1.variant_name == name))
           end) do
      Sealed.record_photo_source!(product, url)
      :ok
    else
      error ->
        Logger.warning("Photo of #{product.slug} not mirrored from #{url}: #{inspect(error)}")
        Sealed.record_photo_attempt!(product)
        :error
    end
  end
end
