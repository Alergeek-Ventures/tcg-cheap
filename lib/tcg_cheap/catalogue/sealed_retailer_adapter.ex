defmodule TcgCheap.Catalogue.SealedRetailerAdapter do
  @moduledoc """
  Source-neutral contract for retailer listing adapters; it performs no HTTP itself.

  Operational callers add a zero-arity `:request_admitter` to adapter options.
  Adapters must invoke it immediately before every outbound request and return its
  error without performing that request. Fixture-only callers may omit it.
  """
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
  @callback source_key() :: String.t()

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
      valid_string?(listing.source_listing_id, 240) and valid_string?(title, 500) and
        valid_string?(listing.direct_url, 2_000) and
        https_url?(listing.direct_url) and
        (is_nil(listing.gtin) or
           SealedIdentifier.valid_ean?(listing.gtin)) and listing.currency == "PLN" and
        listing.stock_status in ["in_stock", "sold_out", "unknown"] and times_ok and
        price != :invalid and (listing.stock_status != "in_stock" or not is_nil(price)) and
        json_payload?(listing.source_payload)

    if valid?, do: {:ok, listing}, else: {:error, :malformed_listing}
  rescue
    _ -> {:error, :malformed_listing}
  end

  def new(_), do: {:error, :malformed_listing}

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp valid_string?(value, maximum),
    do: is_binary(value) and value != "" and byte_size(value) <= maximum

  defp normalize_gtin(nil), do: nil
  defp normalize_gtin(value), do: SealedIdentifier.normalize(:ean, value)

  defp https_url?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme == "https" and is_binary(uri.host) and String.trim(uri.host) != ""
  end

  defp cast_positive_price(nil), do: nil

  defp cast_positive_price(value)
       when is_struct(value, Decimal) or is_integer(value) or is_binary(value) do
    case Decimal.cast(value) do
      {:ok, decimal} ->
        if is_integer(decimal.coef) and Decimal.compare(decimal, Decimal.new(0)) == :gt,
          do: decimal,
          else: :invalid

      :error ->
        :invalid
    end
  end

  defp cast_positive_price(_value), do: :invalid

  defp json_payload?(nil), do: true

  defp json_payload?(value) when is_map(value) do
    match?({:ok, _json}, Jason.encode(value))
  rescue
    _ -> false
  end

  defp json_payload?(_value), do: false
end
