defmodule TcgCheap.Sealed.ShopFeed.WooCommerceListing do
  @moduledoc """
  Reads WooCommerce/Woodmart category HTML without Store API requests or
  query parameters. Each `listing_paths` category uses `/page/N` pagination,
  at most `max_pages` pages, with a three-second minimum request gap.

  The Polish result counter and selected page must agree with the requested
  page, and `HtmlListing` checks the distinct card count against the stated
  total before deduplicating offers across categories. Cards with unreadable
  prices or stock still count towards completeness, but yield no offer.

  Only simple products with an explicit stock class and matching analytics
  stock status are accepted. The rendered current gross PLN price (the `ins`
  amount on sale) must be a single amount; variable products, price ranges
  and backorders are skipped. The card's analytics attribute supplies the
  full title and SKU; only checksum-valid EANs survive normalization.
  Singles are not read.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}
  alias TcgCheap.Sealed.ShopFeed.HtmlListing

  @counter ~r/\AWyświetlanie (\d+)[–-](\d+) z (\d+) wyników\z/u
  @single_counter ~r/\AWyświetlanie wszystkich (\d+) wyników\z/u
  @page_size 12

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, products} <-
           HtmlListing.read_listings(shop, fn path ->
             HtmlListing.read(
               &request(shop, path, &1, req_options),
               shop.max_pages
             )
           end) do
      {:ok, HtmlListing.offers(shop, products, &ShopFeed.sealed_pokemon?(&1, nil))}
    end
  end

  defp request(shop, path, number, req_options) do
    path = if number == 1, do: path, else: "#{path}/page/#{number}"

    with {:ok, document} <- HtmlListing.page(shop, path, req_options, pause_ms: 3_000),
         {:ok, from, to, total} <- counter(document),
         products = Enum.map(Floki.find(document, ".wd-product.product"), &product(shop, &1)),
         true <- from == (number - 1) * @page_size + 1,
         true <- to == min(number * @page_size, total),
         true <- length(products) == to - from + 1,
         true <-
           HtmlListing.text(HtmlListing.first(document, ".page-numbers.current")) ==
             Integer.to_string(number) or total <= @page_size do
      {:ok,
       %{
         number: number,
         last: max(1, div(total + @page_size - 1, @page_size)),
         total: total,
         recognised: Enum.all?(products, & &1.recognised),
         products: products
       }}
    else
      false -> {:error, :malformed_pagination}
      {:error, reason} -> {:error, reason}
    end
  end

  defp counter(document) do
    text = HtmlListing.text(HtmlListing.first(document, ".woocommerce-result-count")) || ""

    case Regex.run(@counter, text) do
      [_, from, to, total] ->
        {:ok, String.to_integer(from), String.to_integer(to), String.to_integer(total)}

      nil ->
        case Regex.run(@single_counter, text) do
          [_, total] -> {:ok, 1, String.to_integer(total), String.to_integer(total)}
          nil -> {:error, :malformed_pagination}
        end
    end
  end

  defp product(shop, node) do
    data = analytics(node)

    %{
      id: node |> Floki.attribute("data-id") |> List.first(),
      title: title(data["item_name"]),
      path: product_path(shop, HtmlListing.attr(node, ".product-image-link a", "href")),
      image: image(HtmlListing.attr(node, ".product-image-link img", "src")),
      price: price(node),
      in_stock: stock(node, data),
      ean: data["sku"],
      recognised: recognised?(node, data)
    }
  end

  # An explicit WooCommerce card may have no offer at all (no price), while
  # still contributing one product to the category's stated total.
  defp recognised?(node, data) do
    id = node |> Floki.attribute("data-id") |> List.first()

    is_binary(id) and is_integer(data["internal_id"]) and
      Integer.to_string(data["internal_id"]) == id and
      is_binary(data["item_name"]) and is_binary(data["productlink"]) and
      data["product_type"] in ["simple", "variable"] and
      data["stockstatus"] in ["instock", "outofstock", "onbackorder"]
  end

  defp title(text) when is_binary(text) do
    case Floki.parse_fragment(text) do
      {:ok, fragment} -> HtmlListing.text(fragment)
      {:error, _reason} -> nil
    end
  end

  defp title(_text), do: nil

  defp image("//" <> rest), do: "https://" <> rest
  defp image(url), do: url

  defp analytics(node) do
    case HtmlListing.attr(node, "[data-gtm4wp_product_data]", "data-gtm4wp_product_data") do
      nil ->
        %{}

      text ->
        case Jason.decode(text) do
          {:ok, %{} = data} -> data
          _ -> %{}
        end
    end
  end

  defp product_path(shop, url) do
    with {:ok, uri} <- ShopFeed.https_url(url, [shop.host]),
         true <- is_nil(uri.query) and is_nil(uri.fragment),
         true <- Regex.match?(shop.product_path, uri.path) do
      uri.path
    else
      _ -> nil
    end
  end

  defp price(node) do
    price = HtmlListing.first(node, ".price")

    current =
      if HtmlListing.first(price || [], "del"),
        do: HtmlListing.first(price || [], "ins"),
        else: price

    # Do not collapse a range (two amounts) into its cheapest variant.
    case Floki.find(current || [], ".amount") do
      [amount] ->
        case HtmlListing.price_text(HtmlListing.text(amount)) do
          {:ok, price} -> price
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp stock(node, data) do
    classes = node |> Floki.attribute("class") |> Enum.join(" ") |> String.split()

    if "product-type-simple" in classes and data["product_type"] == "simple" and
         "onbackorder" not in classes do
      case {"instock" in classes, "outofstock" in classes, data["stockstatus"]} do
        {true, false, "instock"} -> true
        {false, true, "outofstock"} -> false
        _ -> nil
      end
    end
  end
end
