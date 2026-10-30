defmodule TcgCheap.Sealed.Matcher do
  @moduledoc """
  Decides which catalogue product a shop offer is, if any.

  Titles are normalized (lower case, no diacritics, punctuation as spaces) and
  compared by whole words. An offer is first rejected if its title marks a
  non-English edition, a preorder, a multi-item bundle, an empty box, a single
  card or an accessory. Then an exact EAN match wins; otherwise an offer
  matches a product when every one of its terms appears and none of its
  exclusions does. Only a single matching product counts: anything ambiguous
  stays unmatched, because a wrong match would poison the price history.
  """

  alias TcgCheap.Sealed.{Catalogue, Product}

  @global_exclusions [
    # Non-English editions.
    "japan",
    "japanese",
    "jpn",
    "jp",
    "japonski",
    "japonska",
    "japonskie",
    "japonskich",
    "korea",
    "korean",
    "koreanski",
    "koreanska",
    "koreanskie",
    "kor",
    "china",
    "chinese",
    "chinski",
    "chinska",
    "chinskie",
    "chn",
    "simplified chinese",
    "traditional chinese",
    "thai",
    "indonesian",
    "german",
    "niemiecki",
    "niemiecka",
    "french",
    "francuski",
    "spanish",
    "italian",
    "import",
    # Not yet buyable.
    "preorder",
    "pre order",
    "przedsprzedaz",
    "przedpremiera",
    "przedpremierowy",
    "przedpremierowa",
    # Cases and multi-item bundles.
    "case",
    "zestaw",
    "wzorow",
    "komplet",
    # Empty packaging, singles and accessories.
    "empty",
    "pusty",
    "pusta",
    "puste",
    "single",
    "singles",
    "pojedyncza",
    "pojedyncze",
    "sleeves",
    "koszulki",
    "playmat",
    "mata",
    "album",
    "binder only",
    "deck box",
    "toploader",
    "portfolio",
    "code card",
    "kod"
  ]

  @multiples ~r/(?:\A| )(?:x ?\d{1,3}|\d{1,3} ?x)(?: |\z)/

  @type offer :: %{required(:title) => String.t(), optional(:ean) => String.t() | nil}
  @type result :: {:matched, String.t()} | :unmatched | :ambiguous | {:excluded, String.t()}

  @doc "Matches an offer against the catalogue (or the given products)."
  @spec match(offer(), [Product.t()]) :: result()
  def match(offer, products \\ Catalogue.all())

  def match(%{title: title} = offer, products) when is_binary(title) do
    normalized = normalize(title)

    case exclusion(normalized) do
      nil -> match_identity(Map.get(offer, :ean), normalized, products)
      reason -> {:excluded, reason}
    end
  end

  @doc "The product slug for an offer, or nil when it does not match exactly one product."
  @spec product_slug(offer(), [Product.t()]) :: String.t() | nil
  def product_slug(offer, products \\ Catalogue.all()) do
    case match(offer, products) do
      {:matched, slug} -> slug
      _ -> nil
    end
  end

  @doc "Whether a title is globally excluded (non-English, preorder, bundle, accessory…)."
  @spec excluded?(String.t()) :: boolean()
  def excluded?(title) when is_binary(title), do: title |> normalize() |> exclusion() != nil

  @doc "Normalizes a title or term for word-wise comparison."
  @spec normalize(String.t()) :: String.t()
  def normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace("ł", "l")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("&", " and ")
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  defp exclusion(normalized) do
    padded = " " <> normalized <> " "

    cond do
      phrase = Enum.find(@global_exclusions, &contains?(padded, &1)) -> phrase
      Regex.match?(@multiples, normalized) -> "multiple items"
      true -> nil
    end
  end

  defp match_identity(ean, normalized, products) when is_binary(ean) and ean != "" do
    case Enum.filter(products, &(ean in &1.eans)) do
      [product] -> {:matched, product.slug}
      [] -> match_title(normalized, products)
      _many -> :ambiguous
    end
  end

  defp match_identity(_ean, normalized, products), do: match_title(normalized, products)

  defp match_title(normalized, products) do
    padded = " " <> normalized <> " "

    case Enum.filter(products, &title_matches?(&1, padded)) do
      [product] -> {:matched, product.slug}
      [] -> :unmatched
      _many -> :ambiguous
    end
  end

  defp title_matches?(%Product{terms: terms, exclude: exclude}, padded) do
    Enum.all?(terms, fn alternatives -> Enum.any?(alternatives, &contains?(padded, &1)) end) and
      not Enum.any?(exclude, &contains?(padded, &1))
  end

  defp contains?(padded, phrase), do: String.contains?(padded, " " <> phrase <> " ")
end
