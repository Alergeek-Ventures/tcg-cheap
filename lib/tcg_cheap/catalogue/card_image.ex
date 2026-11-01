defmodule TcgCheap.Catalogue.CardImage do
  @moduledoc """
  Builds local image URLs for mirrored TCGdex cards and logos.

  This module deliberately only handles TCGdex asset URLs. It does not fetch or
  otherwise inspect the referenced resource.
  """

  @host "assets.tcgdex.net"
  @qualified_path ~r{/((?:high|low)\.(?:png|jpg|webp))$}
  @known_extension ~r/\.[A-Za-z0-9]+$/

  @doc "Returns the local URL for the stored detail variant of a TCGdex card."
  @spec detail_url(term()) :: String.t() | nil
  def detail_url(url), do: local_url(source_url(url), "detail")

  @doc "Returns the local URL for the stored thumbnail variant of a TCGdex card."
  @spec thumbnail_url(term()) :: String.t() | nil
  def thumbnail_url(url), do: local_url(source_url(url), "thumbnail")

  @doc "Canonical remote source; only the background mirror downloads it."
  @spec source_url(term()) :: String.t() | nil
  def source_url(url) when is_binary(url) do
    with {:ok, uri} <- parse_url(url),
         {:ok, path} <- valid_path(uri.path),
         {:ok, path} <- normalized_path(path) do
      "https://#{@host}#{path}/high.webp"
    else
      _ -> nil
    end
  end

  def source_url(_url), do: nil

  @doc "Canonical WebP source for a TCGdex set logo (base or qualified URL)."
  @spec logo_source_url(term()) :: String.t() | nil
  def logo_source_url(url) when is_binary(url) do
    with {:ok, uri} <- parse_url(url),
         {:ok, path} <- valid_path(uri.path) do
      path = Regex.replace(~r/\.(?:png|jpg|webp)$/, path, "")
      "https://#{@host}#{path}.webp"
    else
      _ -> nil
    end
  end

  def logo_source_url(_url), do: nil

  @doc "Local logo URL; rendering never queries storage or downloads an image."
  @spec logo_url(term()) :: String.t() | nil
  def logo_url(url), do: local_url(logo_source_url(url), "detail")

  @doc "Stable identity shared by all references to a canonical source."
  @spec source_hash(String.t()) :: String.t()
  def source_hash(url), do: :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)

  defp local_url(nil, _size), do: nil
  defp local_url(source, size), do: "/media/tcgdex/#{source_hash(source)}/#{size}"

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
