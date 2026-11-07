defmodule TcgCheap.Sealed.Chasedex do
  @moduledoc """
  Reads the English singles in stock at Chasedex (chasedex.se, Malmö), a
  shop of its own make in front of a Shopify store whose product pages are
  not its card pages, so the cards are read from the shop's own site.

  Two sitemaps say where to look: `/sitemap-sets.xml` names every set page
  (`/set/<slug>`), and `/sitemap-cards-in-stock.xml` (about 17 MB) every card
  page in stock (`/kort/<set slug>-<number>-<name>-<variant>`); a card
  belongs to the longest set slug its own slug starts with. Each set with a
  card in stock, at most `max_pages` of them, is then read once: its page
  lists every card of the set ("Alla kortsidor i …") as "Name 004/165 ·
  Variant · 8 kr", or "· Ej i lager" when sold out, and its JSON-LD
  `CollectionPage` gives the set's name (the offer's category) and the
  number of cards, which the list must hold in full.

  Only cards with a price become offers, all in stock, priced in the shop's
  `currency` (whole kronor, the cheapest condition) with a 0.10 minimum. A
  card's slug is longer than a shop product id may be, so its id is a hash
  of the slug. The list has no images (the card grid shows only the first
  60 cards) and no EANs. Every card is English (the shop sells nothing
  else). `singles_categories` is not read; the sitemaps decide. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Shop, ShopFeed, XmlRecords}

  # The in-stock sitemap lists every card in five languages: about 17 MB for
  # 4,100 cards in November 2026.
  @sitemap_opts [max_body_bytes: 40_000_000]
  @slug ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @price ~r/\A([0-9]{1,6})kr\z/u
  @spaces ~r/[\s\x{a0}]+/u
  @sold_out "Ej i lager"

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, sets} <- sitemap_slugs(shop, "/sitemap-sets.xml", "set", [], req_options),
         {:ok, cards} <-
           sitemap_slugs(shop, "/sitemap-cards-in-stock.xml", "kort", @sitemap_opts, req_options),
         {:ok, stocked} <- stocked_sets(shop, sets, cards),
         {:ok, products} <- read_sets(shop, stocked, req_options) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    end
  end

  # The slugs of a sitemap's pages under `/<section>/` on the shop's host
  # (the other language versions live under their own prefix).
  defp sitemap_slugs(shop, path, section, opts, req_options) do
    prefix = "https://#{shop.host}/#{section}/"

    keep? = &match?({:ok, _slug}, slug(XmlRecords.text(&1, ["loc"]), prefix))

    with {:ok, response} <- ShopFeed.get(shop, path, [], req_options, opts),
         {:ok, [_ | _] = records} <-
           XmlRecords.parse(response.body, ["urlset", "url"], [["loc"]], keep?) do
      {:ok,
       Enum.map(records, fn record ->
         {:ok, slug} = slug(XmlRecords.text(record, ["loc"]), prefix)
         slug
       end)}
    else
      {:ok, []} -> {:error, :empty_sitemap}
      {:error, reason} -> {:error, reason}
    end
  end

  defp slug(loc, prefix) when is_binary(loc) do
    with true <- String.starts_with?(loc, prefix),
         slug = binary_part(loc, byte_size(prefix), byte_size(loc) - byte_size(prefix)),
         true <- Regex.match?(@slug, slug) do
      {:ok, slug}
    else
      false -> :error
    end
  end

  defp slug(_loc, _prefix), do: :error

  # The sets, in sitemap order, with a card in stock; "mega-evolution-promo"
  # wins over "mega-evolution" for "mega-evolution-promo-023-…".
  defp stocked_sets(shop, sets, cards) do
    by_length = Enum.sort_by(sets, &String.length/1, :desc)

    stocked =
      MapSet.new(cards, fn card ->
        Enum.find(by_length, &String.starts_with?(card, &1 <> "-"))
      end)

    case Enum.filter(Enum.uniq(sets), &MapSet.member?(stocked, &1)) do
      [] -> {:error, :empty_sitemap}
      list when length(list) > shop.max_pages -> {:error, :too_many_pages}
      list -> {:ok, list}
    end
  end

  defp read_sets(shop, sets, req_options) do
    Enum.reduce_while(sets, {:ok, []}, fn slug, {:ok, acc} ->
      case read_set(shop, slug, req_options) do
        {:ok, products} -> {:cont, {:ok, acc ++ products}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp read_set(shop, slug, req_options) do
    with {:ok, document} <- HtmlListing.page(shop, "/set/#{slug}", req_options),
         {:ok, name, count} <- collection(document),
         links = Floki.find(document, ~s(details ul li a[href^="/kort/"])),
         true <- (count > 0 and length(links) == count) || {:error, :incomplete_listing} do
      {:ok, Enum.map(links, &product(&1, name))}
    end
  end

  # The set's name and card count from its JSON-LD CollectionPage.
  defp collection(document) do
    document
    |> Floki.find(~s(script[type="application/ld+json"]))
    |> Enum.find_value({:error, :unrecognised_listing}, fn {_tag, _attrs, children} ->
      case Jason.decode(Enum.join(Enum.filter(children, &is_binary/1))) do
        {:ok,
         %{
           "@type" => "CollectionPage",
           "name" => name,
           "mainEntity" => %{"numberOfItems" => count}
         }}
        when is_binary(name) and is_integer(count) ->
          {:ok, name, count}

        _ ->
          nil
      end
    end)
  end

  defp product(link, set_name) do
    %{
      path: link |> Floki.attribute("href") |> List.first(),
      text: HtmlListing.text(link),
      set: set_name
    }
  end

  defp normalize(shop, %{path: "/kort/" <> slug, text: text, set: set_name})
       when is_binary(text) do
    with true <- Regex.match?(@slug, slug),
         [card, variant, status] <- String.split(text, " · "),
         {:ok, price} <- price(status),
         {:ok, title} <- ShopFeed.title("#{card} (#{variant})"),
         {:ok, category} <- ShopFeed.title(set_name),
         url = "https://#{shop.host}/kort/#{slug}",
         {:ok, _uri} <- ShopFeed.https_url(url, [shop.host]) do
      {:ok,
       [
         %{
           shop_product_id: product_id(slug),
           title: title,
           url: url,
           image_url: nil,
           ean: nil,
           price: price,
           in_stock: true,
           kind: :single,
           category: category
         }
       ]}
    else
      :sold_out -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, _product), do: :invalid

  defp price(@sold_out), do: :sold_out

  defp price(text) do
    case Regex.run(@price, String.replace(text, @spaces, "")) do
      [_, kronor] -> ShopFeed.decimal_price(kronor, :single)
      nil -> :error
    end
  end

  # A stable 32-character id: card slugs run past the 40 characters a shop
  # product id may have.
  defp product_id(slug),
    do: :sha256 |> :crypto.hash(slug) |> Base.encode16(case: :lower) |> binary_part(0, 32)
end
