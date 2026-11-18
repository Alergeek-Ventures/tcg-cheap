defmodule TcgCheap.Sealed.ShopFeed.Shoptet do
  @moduledoc """
  Reads sealed products from a Shoptet shop's `listing_paths` and singles
  from its `singles_categories`. Each category is read to the last page its
  pager names, at most `max_pages` pages. The pagination path is taken from
  the listing's links, supporting localized pagers without language rules.

  Shoptet marks every product of a listing (its `.products-page` blocks)
  with microdata (`data-micro="product"`): its id
  (`data-micro-product-id`), name and link,
  and an offer with the price (`data-micro-price`, a plain decimal), its
  currency, which must be the shop's `currency`, and its schema.org
  availability; only `InStock` is in stock, and only on a card that can be
  bought: it has the add-to-cart form, is a product with variants, or shows
  no product code to tell (`purchasable?/1`). Sealed products must name a
  sealed product; singles have a 0.10 minimum and no category (the title
  names the set).
  A card showing a variant code (`product/variant`) that would be an offer in
  stock costs one more request: the product's page, which lists the variants
  and takes the cheapest variant that can be bought as new. Images
  (`data-micro-image`) come from the shop's host or Shoptet's CDN
  (`cdn.myshoptet.com`);
  listings carry no EAN. The pages must form a complete listing, the total
  being the listing's "položek celkem" count (see
  `TcgCheap.Sealed.ShopFeed.HtmlListing.read/2`). See `TcgCheap.Sealed.ShopFeed` for
  the shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  require Logger

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}

  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @path ~r/\A\/[a-z0-9-]+\/\z/
  @in_stock "https://schema.org/InStock"
  # What a card's badges and a variant's name (after `Matcher.normalize/1`)
  # say about a copy that is not new, in the languages of the shops. Some
  # shops put the damage or live-opening warning only on a badge.
  @unsafe_flags ~r/\b(?:rip ?(?:and )?ship|poskozen\w*|poskod\w*|kosmeticke vady|kosmeticka vada|natrzen\w*|promacknut\w*|vadn\w*|rozbalen\w*|otevren\w*|otevir\w*|open box|opened|used|b ware|damaged|2 jakost|druha jakost|serult|bontott|hasznalt|hibas)\b/
  # Failed variant-page requests after which the shop's remaining cards keep
  # the listing's price and stock.
  @max_failed_pages 3
  @variant_key ~r/\A\d+(?:-\d+)*\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host, "cdn.myshoptet.com"]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, sealed} <- sealed_products(shop, req_options) do
      singles =
        HtmlListing.read_singles(shop, fn path, _max_pages ->
          read_category(shop, path, req_options)
        end)

      sealed
      |> Enum.map(&{:sealed, &1})
      |> ShopFeed.with_singles(singles, &offers(shop, &1, req_options))
    end
  end

  defp offers(shop, products, req_options) do
    products = buyable_variants(shop, products, req_options)
    ShopFeed.offers(shop, products, fn product -> normalize(shop, product) end)
  end

  # A card of a product with variants prices its cheapest variant, which may
  # be sold out or a damaged copy. For such a card that would be an offer in
  # stock, the product's page names the variants: the card then takes the
  # cheapest one a buyer can get as new, or is out of stock when there is
  # none. A page that cannot be read leaves the card as it is: the card's own
  # price and stock are still the best reading. A product is asked for once
  # per fetch however many listings show it, and once `@max_failed_pages`
  # requests have failed the shop's other cards are not asked for.
  defp buyable_variants(shop, products, req_options) do
    initial = %{pages: %{}, failed: 0}

    {products, state} =
      Enum.map_reduce(products, initial, fn {kind, product} = tagged, state ->
        if product.variants? and offer_in_stock?(shop, tagged) do
          {state, page} = variant_page(shop, kind, product, state, req_options)
          {{kind, apply_variant(product, page)}, state}
        else
          {tagged, state}
        end
      end)

    log_variant_pages(shop, state.pages, state.failed)
    products
  end

  defp variant_page(shop, kind, product, state, req_options) do
    case Map.fetch(state.pages, product.id) do
      {:ok, page} ->
        {state, page}

      :error when state.failed >= @max_failed_pages ->
        {state, :skipped}

      :error ->
        page = cheapest_variant(shop, kind, product.path, req_options)
        failed = if page == :failed, do: state.failed + 1, else: state.failed
        {%{state | pages: Map.put(state.pages, product.id, page), failed: failed}, page}
    end
  end

  defp apply_variant(product, {:ok, variant}), do: with_variant(product, variant)
  defp apply_variant(product, _unread), do: product

  defp log_variant_pages(shop, pages, failed) do
    counts = pages |> Map.values() |> Enum.frequencies_by(&elem_tag/1)
    without = Map.get(counts, :none, 0)

    if failed > 0 do
      Logger.warning(
        "sealed fetch #{shop.key}: #{failed} variant page requests failed" <>
          if(failed >= @max_failed_pages, do: ", the remaining ones not asked for", else: "")
      )
    end

    if without > 0,
      do: Logger.debug("sealed fetch #{shop.key}: #{without} variant pages without variants")
  end

  defp elem_tag({tag, _variant}), do: tag
  defp elem_tag(tag), do: tag

  defp offer_in_stock?(shop, tagged) do
    match?({:ok, [%{in_stock: true}]}, normalize(shop, tagged))
  end

  defp with_variant(product, nil), do: %{product | in_stock: false}

  defp with_variant(product, %{price: price}),
    do: %{product | price: Decimal.to_string(price, :normal), in_stock: true}

  # `{:ok, nil}`: the page lists variants and none can be bought as new.
  # `:failed`: the request or the page could not be read (a journal keeps that
  # too, so a later step of the fetch does not ask again); `:none`: the page
  # has no variants (a code that merely contains a `/`, like a card number).
  defp cheapest_variant(shop, kind, path, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, path, [], req_options, optional: true),
         {:ok, document} <- ShopFeed.html(response) do
      case variants(document, kind) do
        {:ok, [_ | _] = variants} ->
          {:ok,
           variants
           |> Enum.filter(&(&1.available? and not unsafe_variant?(&1.name)))
           |> Enum.min_by(& &1.price, Decimal, fn -> nil end)}

        _none ->
          :none
      end
    else
      _failed -> :failed
    end
  end

  # Where Shoptet's product page lists the variants: the options of a
  # variant select and the radio buttons of a variant list (price in
  # `data-customerprice`; a variant that cannot be ordered carries
  # `data-disable-button`), or, for a product told apart by parameters, the
  # `necessaryVariantData` of its script, keyed `parameter-value` after the
  # parameter selects' options.
  defp variants(document, kind) do
    case Floki.find(
           document,
           "select[name=priceId] option[data-customerprice], " <>
             "input[type=radio][name=priceId][data-customerprice]"
         ) do
      [] -> split_variants(document, kind)
      nodes -> listed_variants(document, nodes, kind)
    end
  end

  defp listed_variants(document, nodes, kind) do
    variants =
      Enum.map(nodes, fn {tag, _attributes, _children} = node ->
        name =
          case tag do
            "option" -> HtmlListing.text(node)
            "input" -> radio_name(document, node)
          end

        variant(
          name,
          node |> Floki.attribute("data-customerprice") |> List.first(),
          Floki.attribute(node, "data-disable-button") == [],
          kind
        )
      end)

    if Enum.all?(variants, & &1), do: {:ok, variants}, else: :error
  end

  # The value goes into a selector: only digits, as Shoptet writes it.
  defp radio_name(document, node) do
    id = node |> Floki.attribute("value") |> List.first()

    if Regex.match?(~r/\A\d+\z/, id || "") do
      document |> HtmlListing.first(~s([id="variant-name-#{id}"])) |> HtmlListing.text()
    end
  end

  defp split_variants(document, kind) do
    with json when is_binary(json) <- split_variant_json(document),
         {:ok, %{} = data} when map_size(data) > 0 <- Jason.decode(json) do
      variants = Enum.map(data, fn {key, entry} -> split_variant(document, key, entry, kind) end)
      if Enum.all?(variants, & &1), do: {:ok, variants}, else: :error
    else
      _ -> :error
    end
  end

  defp split_variant_json(document) do
    document
    |> Floki.find("script")
    |> Enum.find_value(fn {_tag, _attributes, children} ->
      with [script] when is_binary(script) <- children,
           [_, json] <- Regex.run(~r/necessaryVariantData = (\{.*\});\s*$/m, script) do
        json
      else
        _ -> nil
      end
    end)
  end

  defp split_variant(
         document,
         key,
         %{"priceUnformatted" => price, "isNotSoldOut" => available?},
         kind
       )
       when is_number(price) and is_boolean(available?) do
    # The key goes into a selector: only what Shoptet writes there is let in.
    with true <- Regex.match?(@variant_key, key),
         {:ok, name} <- split_variant_name(document, key) do
      variant(name, plain_price(price), available?, kind)
    else
      _ -> nil
    end
  end

  defp split_variant(_document, _key, _entry, _kind), do: nil

  defp plain_price(price) when is_integer(price), do: Integer.to_string(price)
  defp plain_price(price), do: :erlang.float_to_binary(price, decimals: 2)

  # "29-20": the option with value 20 of the select of parameter 29.
  defp split_variant_name(document, key) do
    values =
      key
      |> String.split("-")
      |> Enum.chunk_every(2)
      |> Enum.map(fn
        [parameter, value] ->
          document
          |> HtmlListing.first(
            ~s(select[data-parameter-id="#{parameter}"] option[value="#{value}"])
          )
          |> HtmlListing.text()

        _odd ->
          nil
      end)

    if Enum.all?(values), do: {:ok, Enum.join(values, " ")}, else: :error
  end

  defp variant(name, price, available?, kind) do
    with name when is_binary(name) <- name,
         {:ok, price} <- ShopFeed.decimal_price(price, kind) do
      %{name: name, price: price, available?: available?}
    else
      _ -> nil
    end
  end

  # A variant name carries the condition of the copy ("Lehké poškození"); the
  # words that deny it ("Bez poškození", "Nepoškozený obal") do not.
  defp unsafe_variant?(name) do
    name = name |> Matcher.normalize() |> String.replace(~r/\bbez \w+/, "")
    Regex.match?(@unsafe_flags, name)
  end

  defp sealed_products(%Shop{singles_only: true}, _req_options), do: {:ok, []}

  defp sealed_products(shop, req_options),
    do: HtmlListing.read_listings(shop, &read_category(shop, &1, req_options))

  defp read_category(shop, path, req_options) do
    with true <- Regex.match?(@path, path),
         {:ok, document} <- HtmlListing.page(shop, path, req_options),
         {:ok, first} <- page(document),
         {:ok, prefix} <- pagination_prefix(document, path, first.last) do
      HtmlListing.read(
        fn
          1 -> {:ok, first}
          number -> request(shop, "#{prefix}#{number}/", req_options)
        end,
        shop.max_pages
      )
    else
      false -> {:error, :invalid_category}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pagination_prefix(_document, _path, 1), do: {:ok, nil}

  defp pagination_prefix(document, path, _last) do
    pattern = Regex.compile!("\\A(" <> Regex.escape(path) <> "[a-z-]+-)[0-9]+/\\z")

    prefix =
      document
      |> Floki.find(".pagination a[href]")
      |> Floki.attribute("href")
      |> Enum.find_value(fn href ->
        case Regex.run(pattern, URI.parse(href).path || "") do
          [_, prefix] -> prefix
          nil -> nil
        end
      end)

    if prefix, do: {:ok, prefix}, else: {:error, :malformed_pagination}
  end

  defp request(shop, path, req_options) do
    with {:ok, document} <- HtmlListing.page(shop, path, req_options), do: page(document)
  end

  defp page(document) do
    # A banner in the middle of a listing splits it into several
    # `.products-page` blocks, of which only the first is `#products`.
    products =
      document |> Floki.find(~s(.products-page [data-micro="product"])) |> Enum.map(&product/1)

    with {:ok, number} <- page_number(document),
         {:ok, total} <- total(document, products) do
      last =
        case HtmlListing.first(document, ".pagination__link--last") do
          nil -> number
          link -> integer(HtmlListing.text(link))
        end

      if is_integer(last),
        do: {:ok, %{number: number, last: max(last, number), total: total, products: products}},
        else: {:error, :malformed_pagination}
    end
  end

  # A listing of one page has no pager.
  defp page_number(document) do
    case HtmlListing.first(document, ".pagination__currentPage") do
      nil ->
        {:ok, 1}

      node ->
        case integer(HtmlListing.text(node)) do
          nil -> {:error, :malformed_pagination}
          number -> {:ok, number}
        end
    end
  end

  # An empty category states no total ("0 produktů") and marks its perex
  # `empty-content-category`; any other page without a total is malformed.
  defp total(document, products) do
    case document |> HtmlListing.first(".itemsTotal strong") |> HtmlListing.text() |> integer() do
      nil when products == [] -> empty_category(document)
      nil -> {:error, :malformed_pagination}
      total -> {:ok, total}
    end
  end

  defp empty_category(document) do
    if HtmlListing.first(document, ".empty-content-category"),
      do: {:ok, 0},
      else: {:error, :malformed_pagination}
  end

  defp integer(nil), do: nil

  defp integer(text) do
    case Integer.parse(String.replace(text, ~r/\s/u, "")) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp product(node) do
    offer = HtmlListing.first(node, ~s([data-micro="offer"]))
    availability = offer && offer |> Floki.attribute("data-micro-availability") |> List.first()

    %{
      id: node |> Floki.attribute("data-micro-product-id") |> List.first(),
      title: node |> HtmlListing.first(~s([data-micro="name"])) |> HtmlListing.text(),
      variants?: variant_code?(node),
      flags: node |> Floki.find(".flags") |> Floki.text(sep: " ") |> Matcher.normalize(),
      path: HtmlListing.attr(node, ~s(a[data-micro="url"]), "href"),
      # Thumbnails load lazily; the microdata names the full image.
      image: HtmlListing.attr(node, "img[data-micro-image]", "data-micro-image"),
      price: offer && offer |> Floki.attribute("data-micro-price") |> List.first(),
      currency: offer && offer |> Floki.attribute("data-micro-price-currency") |> List.first(),
      availability: availability,
      in_stock: availability == @in_stock and purchasable?(node)
    }
  end

  # Some shops mark a sold-out product `InStock` in the microdata. A card
  # that can be bought carries the add-to-cart form (`form.pr-action`); one
  # with only a "Detail" link is either sold out or a product with variants,
  # whose card shows the code of the variant it prices (`product/variant`,
  # as the microdata `sku`). So a card with neither is not in stock. A card
  # without a code shows no evidence either way and keeps its microdata.
  defp purchasable?(node) do
    Floki.find(node, "form.pr-action") != [] or is_nil(sku(node)) or variant_code?(node)
  end

  defp variant_code?(node), do: String.contains?(sku(node) || "", "/")

  defp sku(node), do: node |> HtmlListing.first(~s([data-micro="sku"])) |> HtmlListing.text()

  defp normalize(shop, {kind, product}) do
    with {:ok, title} <- ShopFeed.title(product.title),
         true <- not Regex.match?(@unsafe_flags, product.flags) || :ignore,
         true <- (kind == :single or Matcher.sealed_title?(title)) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product.id),
         {:ok, url} <- product_url(shop, product.path),
         true <- product.currency == shop.currency,
         {:ok, price} <- ShopFeed.decimal_price(product.price, kind),
         availability when is_binary(availability) <- product.availability do
      preorder =
        Matcher.preorder_title?(title <> " " <> product.flags) or
          availability == "https://schema.org/PreOrder"

      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product.image),
           ean: nil,
           price: price,
           in_stock: product.in_stock and not preorder,
           preorder: preorder,
           kind: kind,
           category: nil
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp product_url(shop, "/" <> _rest = path) do
    url = "https://#{shop.host}#{path}"

    with {:ok, uri} <- ShopFeed.https_url(url, [shop.host]),
         true <- is_nil(uri.query) do
      {:ok, url}
    else
      _ -> :error
    end
  end

  defp product_url(_shop, _path), do: :error

  defp image_url(shop, src), do: ShopFeed.image_url(src, image_hosts(shop))
end
