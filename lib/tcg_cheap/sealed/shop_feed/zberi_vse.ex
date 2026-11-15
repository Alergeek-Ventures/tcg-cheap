defmodule TcgCheap.Sealed.ShopFeed.ZberiVse do
  @moduledoc """
  Reads Zberi vse's public shop JSON (`/api.php?action=shop_products`, allowed
  in its robots.txt), one request for its whole catalogue. Each Pokémon item
  with its short `sifra` code, a EUR price and a published sealed kind becomes
  an offer; the slug can be longer than the offer id and belongs in its URL.
  Cards and other games, accessories and mystery/repack items do not.

  An unreleased item or one held back by the shop is a pre-order, never stock.
  Product photos and links stay on the shop's fixed host. See `ShopFeed` for
  validation and request limits.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{Matcher, Shop, ShopFeed}

  @sealed_kinds ~w(sealed_bundle loose_pack sealed_tin sealed_box sealed_deck
                   sealed_blister sealed_tin_display sealed_etb sealed_collection)
  @language_words %{
    "EN" => "EN",
    "JP" => "JPN",
    "JA" => "JPN",
    "CN" => "CN",
    "ZH" => "CN",
    "KR" => "Korean",
    "KO" => "Korean"
  }
  @slug ~r|\A[a-z0-9]+(?:-[a-z0-9]+)*\z|

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, response} <-
           ShopFeed.get(shop, "/api.php", [action: "shop_products"], req_options),
         {:ok, %{"products" => products}} when is_list(products) <-
           ShopFeed.decode(response) do
      {:ok, ShopFeed.offers(shop, products, &normalize(shop, &1))}
    else
      {:ok, _shape} -> {:error, :malformed_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize(shop, %{"igra" => "pokemon"} = product) do
    with {:ok, title} <- title(product),
         true <- sealed?(product, title) || :ignore,
         {:ok, id} <- ShopFeed.product_id(product["sifra"]),
         {:ok, slug} <- slug(product["slug"]),
         {:ok, uri} <- ShopFeed.https_url("https://#{shop.host}/#{slug}", [shop.host]),
         url = URI.to_string(uri),
         {:ok, price} <- ShopFeed.decimal_price(price(product["webPrice"])),
         {:ok, {in_stock, preorder}} <- availability(product, title) do
      {:ok,
       [
         %{
           shop_product_id: id,
           title: title,
           url: url,
           image_url: image_url(shop, product),
           ean: nil,
           price: price,
           in_stock: in_stock,
           preorder: preorder
         }
       ]}
    else
      :ignore -> :ignore
      _ -> :invalid
    end
  end

  defp normalize(_shop, %{"igra" => _game}), do: :ignore
  defp normalize(_shop, _product), do: :invalid

  defp title(%{"igra" => "pokemon", "naziv" => title, "language" => language}) do
    with {:ok, title} <- ShopFeed.title(title) do
      case Map.get(@language_words, language) do
        nil -> :error
        edition -> {:ok, title <> " " <> edition}
      end
    end
  end

  defp title(_product), do: :error

  defp sealed?(%{"kind" => kind}, title) when kind in @sealed_kinds,
    do: Matcher.sealed_title?(title)

  defp sealed?(_product, _title), do: false

  defp price(value) when is_number(value), do: to_string(value)
  defp price(_value), do: nil

  defp slug(value) when is_binary(value) do
    if Regex.match?(@slug, value), do: {:ok, value}, else: :error
  end

  defp slug(_value), do: :error

  defp availability(
         %{"_hasStock" => has_stock, "stockQty" => quantity, "releaseHold" => hold} = product,
         title
       )
       when is_boolean(has_stock) and is_integer(quantity) and quantity >= 0 and is_boolean(hold) do
    with {:ok, future} <- future?(product["releaseDate"]) do
      preorder = hold or future or Matcher.preorder_title?(title)
      {:ok, {has_stock and quantity > 0 and not preorder, preorder}}
    end
  end

  defp availability(_product, _title), do: :error

  defp future?(nil), do: {:ok, false}

  defp future?(value) when is_binary(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         do: {:ok, Date.compare(date, Date.utc_today()) == :gt}
  end

  defp future?(_value), do: :error

  defp image_url(shop, %{"images" => %{"hero" => %{"urlWebp" => "/" <> _ = path}}}),
    do: ShopFeed.image_url("https://#{shop.host}#{path}", image_hosts(shop))

  defp image_url(shop, %{"images" => %{"hero" => %{"url" => "/" <> _ = path}}}),
    do: ShopFeed.image_url("https://#{shop.host}#{path}", image_hosts(shop))

  defp image_url(_shop, _product), do: nil
end
