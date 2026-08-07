defmodule TcgCheap.Catalogue.CardImage do
  @moduledoc """
  Builds image URLs for cards hosted by TCGdex.

  This module deliberately only handles TCGdex asset URLs. It does not fetch or
  otherwise inspect the referenced resource.
  """

  @host "assets.tcgdex.net"
  @qualified_path ~r{/((?:high|low)\.(?:png|jpg|webp))$}
  @known_extension ~r/\.[A-Za-z0-9]+$/

  @doc "Returns the canonical high-resolution WebP URL for a TCGdex card image."
  @spec detail_url(term()) :: String.t() | nil
  def detail_url(url), do: image_url(url, "high.webp")

  @doc "Returns the canonical low-resolution WebP URL for a TCGdex card image."
  @spec thumbnail_url(term()) :: String.t() | nil
  def thumbnail_url(url), do: image_url(url, "low.webp")

  defp image_url(url, suffix) when is_binary(url) do
    with {:ok, uri} <- parse_url(url),
         {:ok, path} <- valid_path(uri.path),
         {:ok, path} <- normalized_path(path) do
      "https://#{@host}#{path}/#{suffix}"
    else
      _ -> nil
    end
  end

  defp image_url(_url, _suffix), do: nil

  defp parse_url(url) do
    uri = URI.parse(url)

    if uri.scheme == "https" and uri.host == @host and uri.port in [nil, 443] and
         is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) do
      {:ok, uri}
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  defp valid_path(path) when is_binary(path) do
    valid? =
      String.starts_with?(path, "/") and
        path != "/" and
        not String.ends_with?(path, "/") and
        String.valid?(path) and
        not Regex.match?(~r/[\s\\\x00-\x1F\x7F]/, path) and
        not Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, path) and
        not Enum.any?(String.split(path, "/"), &(&1 in [".", ".."]))

    if valid?, do: {:ok, path}, else: :error
  end

  defp valid_path(_path), do: :error

  defp normalized_path(path) do
    path =
      case Regex.run(@qualified_path, path, capture: :first) do
        [qualified] -> String.trim_trailing(path, qualified)
        nil -> path
      end

    if path in ["", "/"] or Regex.match?(@known_extension, path) do
      :error
    else
      {:ok, path}
    end
  end
end
