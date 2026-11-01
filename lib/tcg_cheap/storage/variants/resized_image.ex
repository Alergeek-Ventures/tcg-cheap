defmodule TcgCheap.Storage.Variants.ResizedImage do
  @moduledoc """
  AshStorage variant that downsizes an image to `:width` pixels as WebP.

  Images are never upscaled.
  """

  @behaviour AshStorage.Variant

  alias TcgCheap.Storage.Variants.Webp

  @impl true
  def accept?(content_type), do: String.starts_with?(content_type, "image/")

  @impl true
  def transform(source_path, dest_path, opts) do
    width = Keyword.fetch!(opts, :width)

    with {:ok, image} <- Image.thumbnail(source_path, width, resize: :down) do
      Webp.write(image, dest_path)
    end
  end
end
