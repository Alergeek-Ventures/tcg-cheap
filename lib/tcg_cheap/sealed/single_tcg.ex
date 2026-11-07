defmodule TcgCheap.Sealed.SingleTcg do
  @moduledoc """
  Reads the singles of singletcg.pl from the JSON catalogue its own shop
  front loads (`/api/katalog/warianty`): one entry per card variant on sale,
  60 per request (the API's cap), paged by offset (`od`) until a shorter
  page. The shop lists ordinary cards and bulk cards (`bulk=1`) separately,
  so both listings are read, each at most `max_pages` pages. The shop sells
  no sealed products here, so every offer is a single.

  A variant is offered only when it is English (`jezyk`), names a copy for
  sale (`copyId`) outside a bundle (`zestawSlug`; bundles are sold whole)
  and is on its card page (`adres`, `/karty/<set>/<card>/<variant>`). Its
  title is the English card name, number, set and printing ("Yanmega ex 3
  Destined Rivals Holo") plus "NM" for a near-mint copy; its category is the
  set name. The price (`cenaOd`, grosze) is the cheapest copy of the
  variant, with the 0.10 minimum for singles; it is in stock while copies
  remain (`sztuk`). The API carries no EAN. `singles_categories` is not
  read; the listings are fixed. See `TcgCheap.Sealed.ShopFeed` for the
  shared limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @per_page 60
  @card_path ~r/\A\/karty\/[a-z0-9-]{1,100}\/[a-z0-9-]{1,150}\/[a-z0-9-]{1,40}\z/
  @image_path ~r/\A\/skany\/[A-Za-z0-9_.\/-]{1,200}\.(?:webp|png|jpe?g)\z/

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, regular} <- listing(shop, [], req_options),
         {:ok, bulk} <- listing(shop, [bulk: 1], req_options) do
      {:ok, ShopFeed.offers(shop, regular ++ bulk, &normalize(shop, &1))}
    end
  end

  defp listing(shop, params, req_options), do: listing(shop, params, req_options, 0, [])

  defp listing(shop, _params, _req_options, page, _acc) when page >= shop.max_pages,
    do: {:error, :too_many_pages}

  defp listing(shop, params, req_options, page, acc) do
    case request(shop, params ++ [limit: @per_page, od: page * @per_page], req_options) do
      {:ok, variants} when length(variants) == @per_page ->
        listing(shop, params, req_options, page + 1, [variants | acc])

      {:ok, variants} ->
        {:ok, [variants | acc] |> Enum.reverse() |> List.flatten()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(shop, params, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, "/api/katalog/warianty", params, req_options),
         {:ok, %{"warianty" => variants}} when is_list(variants) <- ShopFeed.decode(response) do
      {:ok, variants}
    else
      {:ok, _other} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize(shop, %{"jezyk" => "EN"} = variant) do
    with true <- for_sale_alone?(variant) || :ignore,
         {:ok, id} <- ShopFeed.product_id(variant["variantId"]),
         {:ok, title} <- title(variant),
         {:ok, url} <- shop_url(shop, variant["adres"], @card_path),
         {:ok, price} <- price(variant["cenaOd"]),
         copies when is_integer(copies) and copies >= 0 <- variant["sztuk"] do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, variant["obrazek"]),
           ean: nil,
           price: price,
           in_stock: copies > 0,
           kind: :single,
           category: category(variant["setNazwa"])
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, %{"jezyk" => language}) when is_binary(language), do: :ignore
  defp normalize(_shop, _variant), do: :invalid

  defp for_sale_alone?(%{"copyId" => copy, "zestawSlug" => bundle}),
    do: is_binary(copy) and copy != "" and bundle in [nil, ""]

  defp for_sale_alone?(_variant), do: false

  defp title(%{"nazwaEn" => name, "numer" => number, "setNazwa" => set} = variant)
       when is_binary(name) and is_binary(number) and is_binary(set) do
    [name, number, set, printing(variant["opis"]), condition(variant["kondycja"])]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> ShopFeed.title()
  end

  defp title(_variant), do: :error

  # "Normal" adds nothing; "Holo", "Reverse Holo", "Reverse Holo Pokeball"
  # and the like tell the matcher the printing.
  defp printing("Normal"), do: nil
  defp printing(printing) when is_binary(printing), do: printing
  defp printing(_printing), do: nil

  # Other conditions are left out rather than guessed; every copy listed in
  # November 2026 was near mint.
  defp condition("NEAR_MINT"), do: "NM"
  defp condition(_condition), do: nil

  defp category(set) do
    case ShopFeed.title(set) do
      {:ok, set} -> set
      :error -> nil
    end
  end

  defp price(grosze) when is_integer(grosze) and grosze > 0,
    do: grosze |> Decimal.new() |> Decimal.div(100) |> ShopFeed.price(:single)

  defp price(_grosze), do: :error

  defp shop_url(shop, path, pattern) when is_binary(path) do
    with true <- Regex.match?(pattern, path),
         {:ok, _uri} <- ShopFeed.https_url("https://#{shop.host}#{path}", [shop.host]) do
      {:ok, "https://#{shop.host}#{path}"}
    else
      _ -> :error
    end
  end

  defp shop_url(_shop, _path, _pattern), do: :error

  defp image_url(shop, path) do
    case shop_url(shop, path, @image_path) do
      {:ok, url} -> url
      :error -> nil
    end
  end
end
