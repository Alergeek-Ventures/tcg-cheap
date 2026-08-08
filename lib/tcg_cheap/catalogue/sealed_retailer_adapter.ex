defmodule TcgCheap.Catalogue.SealedRetailerAdapter do
  @moduledoc "Source-neutral contract for retailer listing adapters; it performs no HTTP itself."
  alias TcgCheap.Catalogue.{SealedIdentifier, SearchText}

  defmodule Listing do
    @moduledoc "Normalized listing value returned by an adapter."
    @enforce_keys [
      :source_listing_id,
      :source_title,
      :direct_url,
      :stock_status,
      :first_seen_at,
      :last_seen_at,
      :last_checked_at
    ]
    defstruct [
      :source_listing_id,
      :source_title,
      :normalized_title,
      :direct_url,
      :gtin,
      :current_price_pln,
      :currency,
      :stock_status,
      :first_seen_at,
      :last_seen_at,
      :last_checked_at,
      :source_payload
    ]

    @type t :: %__MODULE__{}
  end

  @callback fetch_listings(retailer :: term(), opts :: keyword()) ::
              {:ok, [Listing.t()]} | {:error, term()}
  @spec new(map()) :: {:ok, Listing.t()} | {:error, term()}
  # This constructor is a pure boundary validator and intentionally checks every contract field.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def new(attrs) when is_map(attrs) do
    listing = struct!(Listing, attrs)

    price = cast_positive_price(listing.current_price_pln)

    listing = %{
      listing
      | source_listing_id: trim(listing.source_listing_id),
        source_title: trim(listing.source_title),
        direct_url: trim(listing.direct_url),
        normalized_title: SearchText.normalize(trim(listing.source_title)),
        gtin: normalize_gtin(listing.gtin),
        currency: listing.currency || "PLN",
        current_price_pln: price
    }

    title = listing.source_title

    times_ok =
      is_struct(listing.first_seen_at, DateTime) and is_struct(listing.last_seen_at, DateTime) and
        is_struct(listing.last_checked_at, DateTime) and
        DateTime.compare(listing.first_seen_at, listing.last_seen_at) != :gt and
        DateTime.compare(listing.last_seen_at, listing.last_checked_at) != :gt

    valid? =
      is_binary(listing.source_listing_id) and String.trim(listing.source_listing_id) != "" and
        is_binary(title) and String.trim(title) != "" and is_binary(listing.direct_url) and
        https_url?(listing.direct_url) and
        (is_nil(listing.gtin) or
           SealedIdentifier.valid_ean?(listing.gtin)) and listing.currency == "PLN" and
        listing.stock_status in ["in_stock", "sold_out", "unknown"] and times_ok and
        price != :invalid and (listing.stock_status != "in_stock" or not is_nil(price))

    if valid?, do: {:ok, listing}, else: {:error, :malformed_listing}
  rescue
    _ -> {:error, :malformed_listing}
  end

  def new(_), do: {:error, :malformed_listing}

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
  defp normalize_gtin(nil), do: nil
  defp normalize_gtin(value), do: SealedIdentifier.normalize(:ean, value)

  defp https_url?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme == "https" and is_binary(uri.host) and String.trim(uri.host) != ""
  end

  defp cast_positive_price(nil), do: nil

  defp cast_positive_price(value) do
    case Decimal.cast(value) do
      {:ok, decimal} ->
        if is_integer(decimal.coef) and Decimal.compare(decimal, Decimal.new(0)) == :gt,
          do: decimal,
          else: :invalid

      :error ->
        :invalid
    end
  end
end
