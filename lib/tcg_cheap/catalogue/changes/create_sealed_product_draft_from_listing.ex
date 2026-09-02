defmodule TcgCheap.Catalogue.Changes.CreateSealedProductDraftFromListing do
  @moduledoc "Derives a hidden canonical product draft from one verified retailer listing."
  use Ash.Resource.Change

  alias TcgCheap.Catalogue.{ExternalImage, ExternalUrl}
  alias TcgCheap.Catalogue.{Retailer, RetailerListing}
  alias TcgCheap.Core

  @max_name_length 240
  @max_slug_length 120
  @type_patterns [
    {~r/\b(etb|elite trainer box)\b/, "elite_trainer_box"},
    {~r/\bbooster bundle\b/, "booster_bundle"},
    {~r/\b(booster|display) box\b/, "booster_box"},
    {~r/\bsleeved booster\b/, "sleeved_booster"},
    {~r/\b(ordinary )?booster( pack)?\b/, "booster_pack"},
    {~r/\b(tin|puszka)\b/, "tin"},
    {~r/\b(deck|talia)\b/, "deck"},
    {~r/\btrainer toolkit\b/, "trainer_toolkit"},
    {~r/\b(collection|box)\b/, "collection_box"}
  ]

  @impl true
  def change(changeset, _opts, context) do
    listing_id = Ash.Changeset.get_argument(changeset, :retailer_listing_id)
    actor = Map.get(context, :actor)

    case Core.get_retailer_listing_by_id(listing_id, actor: actor) do
      {:ok, %RetailerListing{retailer: %Retailer{}} = listing} ->
        changeset
        |> derive(listing)
        |> recheck_mapping(listing_id, actor)

      {:ok, nil} ->
        error(changeset, "retailer listing was not found")

      {:error, reason} ->
        error(changeset, bounded_error(reason))
    end
  end

  defp recheck_mapping(changeset, listing_id, actor) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      query =
        TcgCheap.Catalogue.ListingProductMapping
        |> Ash.Query.for_read(:by_listing, %{retailer_listing_id: listing_id}, actor: actor)
        |> Ash.Query.lock(:for_update)

      case Ash.read_one(query, domain: Core) do
        {:ok, %{status: status}} when status in ["pending", "review"] -> changeset
        {:ok, nil} -> error(changeset, "retailer listing requires a pending or review mapping")
        {:ok, _mapping} -> error(changeset, "retailer listing mapping is no longer reviewable")
        {:error, reason} -> error(changeset, bounded_error(reason))
      end
    end)
  end

  defp derive(changeset, %{status: "active", retailer: %{status: "active"} = retailer} = listing) do
    title = bounded_title(listing.source_title)

    if title == "" or malformed?(listing, retailer) do
      error(changeset, "retailer listing data is malformed")
    else
      source = "retailer:#{retailer.source_key}"
      source_id = listing.source_listing_id

      changeset
      |> Ash.Changeset.force_change_attribute(:publication_status, "draft")
      |> Ash.Changeset.force_change_attribute(:name, title)
      |> Ash.Changeset.force_change_attribute(:slug, slug(title, retailer.source_key, source_id))
      |> Ash.Changeset.force_change_attribute(:product_type, infer_type(title))
      |> Ash.Changeset.force_change_attribute(:source, source)
      |> Ash.Changeset.force_change_attribute(:source_id, source_id)
      |> Ash.Changeset.force_change_attribute(:source_payload, payload(listing, retailer))
      |> Ash.Changeset.force_change_attribute(:source_updated_at, listing.last_checked_at)
      |> Ash.Changeset.force_change_attribute(:last_synced_at, DateTime.utc_now())
      |> copy_image(listing, retailer)
    end
  end

  defp derive(changeset, _listing),
    do: error(changeset, "retailer listing is missing or disabled")

  defp copy_image(changeset, %{image_url: image_url, direct_url: direct_url}, %{
         name: retailer_name
       }) do
    if ExternalImage.valid?(image_url) do
      changeset
      |> Ash.Changeset.force_change_attribute(:image_url, image_url)
      |> Ash.Changeset.force_change_attribute(:image_source, retailer_name)
      |> Ash.Changeset.force_change_attribute(:image_source_url, direct_url)
    else
      changeset
    end
  end

  defp payload(listing, retailer) do
    %{
      "retailer_id" => retailer.id,
      "retailer_source_key" => retailer.source_key,
      "retailer_name" => retailer.name,
      "source_listing_id" => listing.source_listing_id,
      "direct_url" => listing.direct_url,
      "price_pln" => listing.current_price_pln,
      "stock_status" => listing.stock_status
    }
  end

  defp malformed?(listing, retailer) do
    not (is_binary(listing.source_listing_id) and String.trim(listing.source_listing_id) != "" and
           ExternalUrl.valid?(listing.direct_url) and
           is_binary(retailer.source_key) and String.trim(retailer.source_key) != "")
  end

  defp bounded_title(title) when is_binary(title),
    do: title |> String.trim() |> String.slice(0, @max_name_length)

  defp bounded_title(_), do: ""

  defp slug(title, source_key, listing_id) do
    readable =
      title
      |> ascii()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> case do
        "" -> "product"
        value -> value
      end

    digest =
      :crypto.hash(:sha256, "#{source_key}:#{listing_id}")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    String.slice(readable, 0, @max_slug_length - byte_size(digest) - 1) <> "-" <> digest
  end

  defp ascii(value) do
    value
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(~r/[^\x00-\x7F]/, "")
  end

  defp infer_type(title) do
    normalized = String.downcase(title)

    Enum.find_value(@type_patterns, "other", fn {pattern, type} ->
      if Regex.match?(pattern, normalized), do: type
    end)
  end

  defp error(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :retailer_listing_id, message: message)

  defp bounded_error(error) do
    error |> Exception.message() |> String.replace(~r/\s+/, " ") |> String.slice(0, 240)
  rescue
    _ -> "could not load retailer listing"
  end
end
