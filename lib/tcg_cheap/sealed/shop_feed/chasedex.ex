defmodule TcgCheap.Sealed.ShopFeed.Chasedex do
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
  number of cards, which the list must hold in full. The page's data also
  names the Shopify variant of each card in stock (`variantId`).

  Only cards with a price become offers, all in stock, priced in the shop's
  `currency` (whole kronor, the cheapest condition) with a 0.10 minimum. A
  card's slug is longer than a shop product id may be, so its id is a hash
  of the slug. The list has no images (the card grid shows only the first
  60 cards) and no EANs. Every card is English (the shop sells nothing
  else). `singles_categories` is not read; the sitemaps decide. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.

  The shop charges buyers of another country prices of its own (Shopify
  Markets), in euros in every country it delivers to, which its deliveries
  record (`price_currency` of `TcgCheap.Sealed.Shop`'s `deliveries`). They are
  read as the shop's own pages read them, from the Shopify Storefront API:
  the home page names the shop's script that holds the API's address,
  version and public access token, and for each such country the variants of
  all cards read are asked for, 250 per request, 3 s apart
  (`@in_context country`). Every offer carries what it costs there
  (`market_prices`); a card whose variant is unknown or which the API does not
  price for a country has no price in that country. A failed read, or an
  answer in another currency than the one recorded, fails the fetch like any
  other page, as does an answer that does not cover the variants asked, or
  one that leaves more than 2 % of the cards in stock without a price in some
  such country (`TcgCheap.Sealed.Refresh` leaves a card without a Polish price
  out of every market, so a lost price must not pass as a small shop). A fetch
  makes 2 + countries × ⌈variants / 250⌉ requests on top of its sitemaps and
  set pages (the home page and the script once, the batches for each country),
  and logs how many cards it read, priced and left out.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  require Logger

  alias TcgCheap.Sealed.{Shop, ShopFeed, Shops}

  alias TcgCheap.Sealed.ShopFeed.{HtmlListing, XmlRecords}

  # The in-stock sitemap lists every card in five languages: about 17 MB for
  # 4,100 cards in November 2026.
  @sitemap_opts [max_body_bytes: 40_000_000]
  @slug ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @price ~r/\A([0-9]{1,6})kr\z/u
  @spaces ~r/[\s\x{a0}]+/u
  @sold_out "Ej i lager"

  # The set page's data lists each card by slug with its price and, when it is
  # in stock, its Shopify variant.
  @variant ~r/slug:"([a-z0-9-]+)",variant:"[a-z0-9_-]+",label:"[^"]*",price:([0-9]+),inStock:!0,quantity:[0-9]+,variantId:"(gid:\/\/shopify\/ProductVariant\/[0-9]+)"/
  @script_path ~r/\A\/assets\/shopify-[A-Za-z0-9_-]+\.js\z/
  @storefront_host ~r/`([a-z0-9-]+\.myshopify\.com)`/
  @storefront_version ~r/`(20[0-9]{2}-[0-9]{2})`/
  @storefront_token ~r/`([0-9a-f]{32})`/
  @storefront_query "query MarketPrices($ids: [ID!]!, $country: CountryCode!) @inContext(country: $country) { nodes(ids: $ids) { ... on ProductVariant { id price { amount currencyCode } } } }"
  @storefront_batch 250
  @max_left_out_percent 2
  # Slower than the reader's other requests: these are the shop's API.
  @storefront_pause_ms 3_000

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, sets} <- sitemap_slugs(shop, "/sitemap-sets.xml", "set", [], req_options),
         {:ok, cards} <-
           sitemap_slugs(shop, "/sitemap-cards-in-stock.xml", "kort", @sitemap_opts, req_options),
         {:ok, stocked} <- stocked_sets(shop, sets, cards),
         {:ok, products} <- read_sets(shop, stocked, req_options),
         {:ok, prices} <- market_prices(shop, products, req_options) do
      offers = ShopFeed.offers(shop, products, &normalize(shop, &1, prices))
      check_market_prices(shop, offers)
    end
  end

  # A card in stock must have a price in every country the shop prices apart:
  # `TcgCheap.Sealed.Refresh` leaves out of every market, Sweden's included, a
  # singles offer without a price for Poland, so a read that lost the prices
  # (a token that sees no market, a card the page data does not match) must
  # not pass as the whole shop. A few cards may lack one (a variant the shop
  # does not sell to a country); more fail the fetch.
  defp check_market_prices(shop, offers) do
    countries = shop |> Shops.price_currencies() |> Map.keys()

    left_out =
      Enum.count(offers, fn offer ->
        Enum.any?(countries, &(not is_map_key(offer.market_prices, &1)))
      end)

    Logger.info(
      "sealed fetch #{shop.key}: #{length(offers)} cards read from set pages, " <>
        "#{length(offers) - left_out} with country prices, #{left_out} left out"
    )

    if countries != [] and left_out * 100 > length(offers) * @max_left_out_percent,
      do: {:error, {:incomplete_market_prices, left_out, length(offers)}},
      else: {:ok, offers}
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
         true <- (count > 0 and length(links) == count) || {:error, :incomplete_listing},
         variants = variants(document),
         true <- (variants != %{} or not Enum.any?(links, &in_stock?/1)) || {:error, :no_variants} do
      {:ok, Enum.map(links, &product(&1, name, variants))}
    end
  end

  # The variant of each card in stock on a set page, by the card's slug, with
  # the price the page's data gives it (in kronor).
  defp variants(document) do
    data = for {"script", _attrs, children} <- Floki.find(document, "script"), do: children

    for text <- List.flatten(data),
        is_binary(text),
        [_, slug, price, variant] <- Regex.scan(@variant, text),
        into: %{},
        do: {slug, {price, variant}}
  end

  defp in_stock?(link), do: not String.ends_with?(HtmlListing.text(link), " · " <> @sold_out)

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

  defp product(link, set_name, variants) do
    path = link |> Floki.attribute("href") |> List.first()

    %{
      path: path,
      text: HtmlListing.text(link),
      set: set_name,
      variant: Map.get(variants, String.replace_prefix(path || "", "/kort/", ""))
    }
  end

  defp normalize(shop, %{path: "/kort/" <> slug, text: text, set: set_name} = product, prices)
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
           market_prices: card_market_prices(product, price, prices),
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

  defp normalize(_shop, _product, _prices), do: :invalid

  # The price the set page's data gives a card must be the listed one for its
  # variant to be this card's. A price the shop wrote wrongly for a country is
  # no price there.
  defp card_market_prices(%{variant: {listed, variant}}, price, prices) do
    if Decimal.equal?(Decimal.new(listed), price) do
      for {country, %{price: raw, currency: currency}} <- Map.get(prices, variant, %{}),
          {:ok, price} <- [ShopFeed.decimal_price(raw, :single)],
          into: %{},
          do: {country, %{price: price, currency: currency}}
    else
      %{}
    end
  end

  defp card_market_prices(_product, _price, _prices), do: %{}

  # What each variant costs in the countries the shop prices apart, by
  # variant id and country, as the shop wrote it.
  defp market_prices(shop, products, req_options) do
    ids =
      for %{variant: {_price, variant}} <- products, uniq: true, do: variant

    case shop |> Shops.price_currencies() |> Enum.sort() do
      [] ->
        {:ok, %{}}

      markets ->
        with {:ok, storefront} <- storefront(shop, req_options) do
          read_markets(shop, storefront, markets, Enum.sort(ids), req_options)
        end
    end
  end

  defp read_markets(shop, storefront, markets, ids, req_options) do
    for market <- markets,
        batch <- Enum.chunk_every(ids, @storefront_batch),
        reduce: {:ok, %{}} do
      {:ok, prices} -> read_batch(shop, storefront, market, batch, req_options, prices)
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_batch(shop, storefront, {country, currency}, ids, req_options, prices) do
    params = [
      query: @storefront_query,
      variables: Jason.encode!(%{ids: ids, country: country})
    ]

    req_options =
      Keyword.update(
        req_options,
        :headers,
        [{"x-shopify-storefront-access-token", storefront.token}],
        &[{"x-shopify-storefront-access-token", storefront.token} | &1]
      )

    with {:ok, response} <-
           ShopFeed.get(
             %{shop | feed_host: storefront.host},
             "/api/#{storefront.version}/graphql.json",
             params,
             req_options,
             pause_ms: @storefront_pause_ms
           ),
         {:ok, %{"data" => %{"nodes" => nodes}} = body}
         when is_list(nodes) and not is_map_key(body, "errors") <-
           ShopFeed.decode(response),
         true <- answers_ids?(nodes, ids) || {:error, :incomplete_response},
         {:ok, prices} <- put_prices(nodes, {country, currency}, prices) do
      {:ok, prices}
    else
      {:ok, _other} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  # The API answers one node per id asked, in order; a variant it does not
  # know is null. A short answer, or a node for another variant, is not an
  # answer to what was asked.
  defp answers_ids?(nodes, ids) do
    length(nodes) == length(ids) and
      nodes |> Enum.zip(ids) |> Enum.all?(&node_for?/1)
  end

  defp node_for?({nil, _id}), do: true
  defp node_for?({%{"id" => id}, id}), do: true
  defp node_for?(_other), do: false

  # A variant the API does not know answers null: it has no price there.
  defp put_prices(nodes, {country, currency}, prices) do
    Enum.reduce_while(nodes, {:ok, prices}, fn
      %{"id" => id, "price" => %{"amount" => amount, "currencyCode" => ^currency}}, {:ok, acc}
      when is_binary(id) ->
        {:cont,
         {:ok,
          Map.update(
            acc,
            id,
            %{country => %{price: amount, currency: currency}},
            &Map.put(&1, country, %{price: amount, currency: currency})
          )}}

      %{"price" => %{"currencyCode" => _other}}, _acc ->
        {:halt, {:error, :unexpected_currency}}

      nil, acc ->
        {:cont, acc}

      _node, _acc ->
        {:halt, {:error, :malformed_response}}
    end)
  end

  # The Storefront API's address, version and public access token, which the
  # shop's own pages carry in the script the home page preloads.
  defp storefront(shop, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, "/", [], req_options),
         {:ok, home} <- ShopFeed.html(response),
         [path | _] <- script_paths(home),
         {:ok, response} <- ShopFeed.get(shop, path, [], req_options),
         [[_, host]] <- Regex.scan(@storefront_host, response.body) |> Enum.uniq(),
         [_, version] <- Regex.run(@storefront_version, response.body),
         [_, token] <- Regex.run(@storefront_token, response.body) do
      {:ok, %{host: host, version: version, token: token}}
    else
      {:error, reason} -> {:error, reason}
      _unrecognised -> {:error, :unrecognised_storefront}
    end
  end

  defp script_paths(document) do
    for href <- Floki.attribute(document, ~s(link[rel="modulepreload"]), "href"),
        Regex.match?(@script_path, href),
        do: href
  end

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
