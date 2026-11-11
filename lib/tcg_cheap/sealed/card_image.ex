defmodule TcgCheap.Sealed.CardImage do
  @moduledoc """
  Builds local image URLs for mirrored TCGdex cards and logos, for photos of
  what sealed products hold, and for expansion logos set by an agent or admin.

  Cards and TCGdex set logos are TCGdex asset URLs only; contents photos and
  the expansion logos set by an agent or admin may come from any allowlisted
  image host. It does not fetch or otherwise inspect the referenced resource.
  """

  alias TcgCheap.Sealed.ExternalImage

  @host "assets.tcgdex.net"
  @limitless "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci"
  # TCGdex lacks some Sword & Shield promos (Special Delivery Bidoof SWSH177,
  # Pikachu SWSH074) and Limitless TCG has none; pokemontcg.io has them.
  @pokemontcg "https://images.pokemontcg.io"
  # 30th Classic Collection shares "30C" with 30th Celebration, whose 30C_001
  # is Exeggcute, not the collection's Charizard: Limitless TCG files the
  # collection as 30C_CC1–CC30, in another order than TCGdex's numbers
  # (matched by name and checked by eye on 2026-11-07).
  @classic_collection %{
    "001" => "CC2",
    "002" => "CC8",
    "003" => "CC11",
    "004" => "CC20",
    "005" => "CC3",
    "006" => "CC9",
    "007" => "CC5",
    "008" => "CC25",
    "009" => "CC22",
    "010" => "CC13",
    "011" => "CC14",
    "012" => "CC27",
    "013" => "CC24",
    "014" => "CC1",
    "015" => "CC4",
    "016" => "CC19",
    "017" => "CC23",
    "018" => "CC15",
    "019" => "CC16",
    "020" => "CC17",
    "021" => "CC18",
    "022" => "CC12",
    "023" => "CC21",
    "024" => "CC6",
    "025" => "CC10",
    "026" => "CC28",
    "027" => "CC29",
    "028" => "CC26",
    "029" => "CC7",
    "030" => "CC30"
  }
  @limitless_scan ~r"\Ahttps://limitlesstcg\.nyc3\.cdn\.digitaloceanspaces\.com/tpci/(?:([A-Z0-9]+)/\1_(?:\d{3,}|[A-Z])|CRZ/CRZ_GG[1-9]\d?|30C/30C_CC[1-9]\d?)_R_EN_LG\.png\z"
  @pokemontcg_scan ~r"\Ahttps://images\.pokemontcg\.io/swshp/SWSH\d{3}_hires\.png\z"
  @qualified_path ~r{/((?:high|low)\.(?:png|jpg|webp))$}
  @known_extension ~r/\.[A-Za-z0-9]+$/
  @image_extension ~r/\.(?:png|jpg|webp)$/
  @unsafe_path_character ~r/[\s\\\x00-\x1F\x7F]/
  @bare_percent ~r/%(?![0-9A-Fa-f]{2})/

  @doc """
  A catalogue card's image sources, best first: the card in its set's TCGdex
  card image directory, then Limitless TCG's scan. Pages show the first one
  mirrored; TCGdex lacks the images of some sets (Shining Legends, MEP Black
  Star Promos, a new set not listed yet) and of some cards (SVP 175). A set
  with an unofficial card list has Limitless TCG's scans once its official
  code was recorded with it.
  """
  @spec single_sources(map(), String.t()) :: [String.t()]
  def single_sources(set, number) do
    [tcgdex_card(set, number), limitless_scan(set, number), pokemontcg_scan(set, number)]
    |> Enum.reject(&is_nil/1)
  end

  defp tcgdex_card(%{card_images_url: "" <> directory}, number),
    do: source_url(directory <> "/" <> number)

  defp tcgdex_card(_set, _number), do: nil

  defp limitless_scan(%{tcgdex_id: "30th-c"}, number) do
    if code = Map.get(@classic_collection, number),
      do: card_source_url("#{@limitless}/30C/30C_#{code}_R_EN_LG.png")
  end

  # Galarian Gallery uses Crown Zenith's directory and its unpadded GG number.
  defp limitless_scan(%{abbreviation: "CRZ:GG"}, "GG" <> digits) do
    if Regex.match?(~r/\A\d{2}\z/, digits),
      do: card_source_url("#{@limitless}/CRZ/CRZ_GG#{String.to_integer(digits)}_R_EN_LG.png")
  end

  # Other scans use the official set code and the number padded to three
  # digits; a one-letter number (30th Celebration's Mew R, G and B) stays as is.
  defp limitless_scan(%{abbreviation: "" <> code}, number) do
    cond do
      Regex.match?(~r/\A\d+\z/, number) ->
        card_source_url(
          "#{@limitless}/#{code}/#{code}_#{String.pad_leading(number, 3, "0")}_R_EN_LG.png"
        )

      Regex.match?(~r/\A[A-Z]\z/, number) ->
        card_source_url("#{@limitless}/#{code}/#{code}_#{number}_R_EN_LG.png")

      true ->
        nil
    end
  end

  defp limitless_scan(_set, _number), do: nil

  defp pokemontcg_scan(%{tcgdex_id: "swshp"}, "SWSH" <> digits = number) do
    if Regex.match?(~r/\A\d{3}\z/, digits),
      do: card_source_url("#{@pokemontcg}/swshp/#{number}_hires.png")
  end

  defp pokemontcg_scan(_set, _number), do: nil

  @doc "30th Classic Collection's Limitless TCG scan codes by TCGdex card number."
  @spec classic_collection() :: %{String.t() => String.t()}
  def classic_collection, do: @classic_collection

  @doc "Returns the local URL for the stored detail variant of a card image."
  @spec detail_url(term()) :: String.t() | nil
  def detail_url(url), do: local_url(card_source_url(url), "detail")

  @doc "Returns the local URL for the stored thumbnail variant of a card image."
  @spec thumbnail_url(term()) :: String.t() | nil
  def thumbnail_url(url), do: local_url(card_source_url(url), "thumbnail")

  @doc "Canonical remote source of a card image: a TCGdex card or a Limitless TCG scan."
  @spec card_source_url(term()) :: String.t() | nil
  def card_source_url(url) when is_binary(url) do
    if Regex.match?(@limitless_scan, url) or Regex.match?(@pokemontcg_scan, url),
      do: url,
      else: source_url(url)
  end

  def card_source_url(_url), do: nil

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
      path = Regex.replace(@image_extension, path, "")
      "https://#{@host}#{path}.webp"
    else
      _ -> nil
    end
  end

  def logo_source_url(_url), do: nil

  @doc "Local logo URL; rendering never queries storage or downloads an image."
  @spec logo_url(term()) :: String.t() | nil
  def logo_url(url), do: logo_version(local_url(logo_source_url(url), "detail"))

  @doc "Source of a product contents photo: any allowlisted image URL, kept as given."
  @spec photo_source_url(term()) :: String.t() | nil
  def photo_source_url(url) do
    if ExternalImage.valid?(url), do: url
  end

  @doc "Local URL of a mirrored contents photo in `size` (thumbnail or detail)."
  @spec photo_url(term(), String.t()) :: String.t() | nil
  def photo_url(url, size), do: local_url(photo_source_url(url), size)

  @doc "Source of an expansion logo set by an agent or admin: any allowlisted image URL, kept as given."
  @spec expansion_logo_source_url(term()) :: String.t() | nil
  def expansion_logo_source_url(url), do: photo_source_url(url)

  @doc "Local URL of a mirrored expansion logo set by an agent or admin."
  @spec expansion_logo_url(term()) :: String.t() | nil
  def expansion_logo_url(url),
    do: logo_version(local_url(expansion_logo_source_url(url), "detail"))

  @doc "Stable identity shared by all references to a canonical source."
  @spec source_hash(String.t()) :: String.t()
  def source_hash(url), do: :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)

  # Logos are mirrored again with their margins trimmed and the old files are
  # deleted; a new URL keeps browsers off redirects cached for the old ones.
  defp logo_version(nil), do: nil
  defp logo_version(url), do: url <> "?v=trimmed"

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
        not Regex.match?(@unsafe_path_character, path) and
        not Regex.match?(@bare_percent, path) and
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
