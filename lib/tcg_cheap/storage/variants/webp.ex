defmodule TcgCheap.Storage.Variants.Webp do
  @moduledoc """
  Writes image variants as WebP together with an inline placeholder.

  The placeholder is a tiny WebP encoded as a data URI and stored in the variant
  blob metadata under `placeholder`. The guide renders it blurred while the full
  image loads, so it has to stay small enough to ship inline with every record.
  """

  @placeholder_width 8
  @write_options [suffix: ".webp", strip_metadata: true]

  @doc "Writes `image` to `dest_path` and returns the AshStorage variant metadata."
  @spec write(Vix.Vips.Image.t(), Path.t()) :: {:ok, map()} | {:error, term()}
  def write(image, dest_path) do
    with {:ok, webp} <- Image.write(image, :memory, @write_options),
         :ok <- write_file(dest_path, webp),
         {:ok, placeholder} <- placeholder(webp) do
      {:ok, %{content_type: "image/webp", placeholder: placeholder}}
    end
  end

  # Built from the encoded variant: images opened from a file are streamed
  # sequentially by libvips and cannot be read a second time.
  defp placeholder(variant_webp) do
    with {:ok, image} <- Image.from_binary(variant_webp),
         {:ok, tiny} <- Image.thumbnail(image, @placeholder_width),
         {:ok, webp} <- Image.write(tiny, :memory, @write_options) do
      {:ok, "data:image/webp;base64," <> Base.encode64(webp)}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # dest_path is a temporary path allocated by AshStorage.VariantGenerator.
  defp write_file(dest_path, data), do: File.write(dest_path, data)
end
