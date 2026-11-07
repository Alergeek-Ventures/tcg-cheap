defmodule TcgCheap.Sealed.Pokemonki do
  @moduledoc """
  Reads the English singles of pokemonki.pl, a shop on its own PHP site
  with no feed or JSON listing: its set index (`/sets`) names every set it
  sells, and each set's card listing (`/cards.php?set=<name>`, 25 cards a
  page, both printings, in stock only) is read to its last page, each at
  most `max_pages` pages, with `TcgCheap.Sealed.HtmlListing.read/2`. The
  pager names the current page and links to the last; the listing states
  no product total (its "Łącznie" counts copies, not cards).

  Every card is a single: one offer per card and printing (the cart form's
  `card_id` and `variant`), titled with its name, set code and number and
  printing ("Bulbasaur MEW 001", "Vulpix MEW 037 Reverse Holo"), with the
  set's name as its category. Its price is the listed one (0.10 minimum);
  it is in stock while copies remain ("Dostępne: N"). Listings carry no EAN.
  `singles_categories` is not read; the set index decides. See
  `TcgCheap.Sealed.ShopFeed` for the shared limits.

  Requests are paced 500 ms apart instead of the usual 1 s: the shop has
  about 175 listing pages (November 2026), which at the usual pace take
  about 230 s, too close to the job's 5-minute timeout; the pages answer in
  0.1–0.6 s.
  """

  @behaviour TcgCheap.Sealed.ShopFeed

  alias TcgCheap.Sealed.{HtmlListing, Shop, ShopFeed}

  @request_opts [pause_ms: 500]
  @max_sets 100
  @set_link ~r/\A\/cards\.php\?set=([^&]{1,120})\z/
  @set_name ~r/\A[\p{L}\p{N} &'’.:-]{1,80}\z/u
  @card_id ~r/\A[a-z0-9]{1,20}-[A-Za-z0-9]{1,10}\z/
  @card_path ~r/\A\/[a-z0-9-]{1,200}\z/
  @stock ~r/\ADostępne: ([0-9]{1,5})\z/u

  @impl true
  def image_hosts(%Shop{host: host}), do: [host]

  @impl true
  def fetch(%Shop{} = shop, req_options) do
    with {:ok, sets} <- sets(shop, req_options),
         {:ok, products} <- read_sets(shop, sets, req_options) do
      {:ok, HtmlListing.offers(shop, Enum.map(products, &{:single, &1}), fn _title -> false end)}
    end
  end

  defp sets(shop, req_options) do
    with {:ok, document} <- document(shop, "/sets", [], req_options) do
      sets =
        document
        |> Floki.attribute("a", "href")
        |> Enum.flat_map(&set_name/1)
        |> Enum.uniq()

      case sets do
        [] -> {:error, :unrecognised_listing}
        sets when length(sets) > @max_sets -> {:error, :too_many_pages}
        sets -> {:ok, sets}
      end
    end
  end

  defp set_name(href) do
    with [_, encoded] <- Regex.run(@set_link, href),
         name = URI.decode_www_form(encoded),
         true <- String.valid?(name) and Regex.match?(@set_name, name) do
      [name]
    else
      _ -> []
    end
  end

  defp read_sets(shop, sets, req_options) do
    Enum.reduce_while(sets, {:ok, []}, fn set, {:ok, acc} ->
      case HtmlListing.read(&request(shop, set, req_options, &1), shop.max_pages) do
        {:ok, products} -> {:cont, {:ok, acc ++ products}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp request(shop, set, req_options, number) do
    params = [set: set, sort: "number_asc", variant: "all", page: number]

    with {:ok, document} <- document(shop, "/cards.php", params, req_options),
         {:ok, current, last} <- pages(document) do
      {:ok,
       %{
         number: current,
         last: last,
         total: nil,
         products: document |> Floki.find("main.grid article.card") |> Enum.map(&product(&1, set))
       }}
    end
  end

  defp document(shop, path, params, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, path, params, req_options, @request_opts),
         do: ShopFeed.html(response)
  end

  # A one-page listing has no pager. Otherwise the pager shows the current
  # page as text and links to the others, the last always among them.
  defp pages(document) do
    case Floki.find(document, "nav.pager") do
      [] ->
        {:ok, 1, 1}

      pager ->
        current = pager |> HtmlListing.first("span.current") |> HtmlListing.text() |> integer()
        linked = pager |> Floki.find("a") |> Enum.map(&(&1 |> HtmlListing.text() |> integer()))

        if is_integer(current),
          do: {:ok, current, Enum.max([current | Enum.filter(linked, &is_integer/1)])},
          else: {:error, :malformed_pagination}
    end
  end

  defp product(card, set) do
    %{
      id: product_id(card),
      title: title(card),
      path: card_path(HtmlListing.attr(card, "a", "href")),
      image: HtmlListing.attr(card, "div.img img", "src"),
      price: card |> HtmlListing.first("span.price") |> HtmlListing.text() |> price(),
      in_stock: card |> HtmlListing.first("div.stock") |> HtmlListing.text() |> in_stock(),
      category: set
    }
  end

  defp product_id(card) do
    card_id = HtmlListing.attr(card, ~s(input[name="card_id"]), "value")
    variant = HtmlListing.attr(card, ~s(input[name="variant"]), "value")

    if is_binary(card_id) and Regex.match?(@card_id, card_id) and variant in ["normal", "holo"],
      do: "#{card_id}-#{variant}"
  end

  # The listing calls the reverse holo printing "holo" in its cart form and
  # "Reverse Holo" in the card's text.
  defp title(card) do
    name = card |> HtmlListing.first("h2.name") |> HtmlListing.text()
    code = card |> HtmlListing.first("span.sc") |> HtmlListing.text()
    printing = card |> HtmlListing.first("span.meta-variant") |> HtmlListing.text()

    if is_binary(name) and is_binary(code),
      do: Enum.join(Enum.reject([name, code, printing], &is_nil/1), " ")
  end

  defp card_path(path) when is_binary(path) do
    if Regex.match?(@card_path, path), do: path
  end

  defp card_path(_path), do: nil

  defp price(text) do
    case HtmlListing.price_text(text) do
      {:ok, decimal} -> decimal
      :error -> nil
    end
  end

  defp in_stock(nil), do: nil

  defp in_stock(text) do
    case Regex.run(@stock, text) do
      [_, copies] -> String.to_integer(copies) > 0
      nil -> nil
    end
  end

  defp integer(nil), do: nil

  defp integer(text) do
    case Integer.parse(text) do
      {value, ""} when value > 0 -> value
      _ -> nil
    end
  end
end
