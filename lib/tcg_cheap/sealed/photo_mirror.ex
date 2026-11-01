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

  alias TcgCheap.Catalogue.ExternalImage
  alias TcgCheap.Sealed

  @max_bytes 15 * 1024 * 1024
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

    with true <- ExternalImage.valid?(url) || {:error, :host_not_allowed},
         {:ok, body, type} <- download(url, req_options),
         {:ok, _attached} <-
           AshStorage.Operations.attach(product, :photo, body,
             filename: "#{product.slug}.#{@types[type]}",
             content_type: type
           ) do
      Sealed.record_photo_source!(product, url)
      :ok
    else
      # Not tried again until the shop photo changes; the page keeps the shop's link.
      error ->
        Logger.warning("Photo of #{product.slug} not mirrored from #{url}: #{inspect(error)}")
        Sealed.record_photo_source!(product, url)
        :error
    end
  end

  defp download(url, req_options) do
    [
      url: url,
      decode_body: false,
      connect_options: [timeout: 5_000],
      receive_timeout: 20_000,
      max_redirects: 3,
      retry: false,
      headers: [{"user-agent", "TcgCheap/1.0 (buying guide)"}]
    ]
    |> Req.new()
    |> Req.merge(req_options)
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: body} = response}
      when byte_size(body) <= @max_bytes ->
        type =
          response |> Req.Response.get_header("content-type") |> List.first("") |> media_type()

        if Map.has_key?(@types, type),
          do: {:ok, body, type},
          else: {:error, {:not_an_image, type}}

      {:ok, %Req.Response{status: 200}} ->
        {:error, :too_large}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, exception} ->
        {:error, {:transport, exception.__struct__}}
    end
  end

  defp media_type(header),
    do: header |> String.split(";") |> hd() |> String.trim() |> String.downcase()
end
