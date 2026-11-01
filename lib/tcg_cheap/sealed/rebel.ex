defmodule TcgCheap.Sealed.Rebel do
  @moduledoc """
  Collects suggested retail prices (SCD, gross PLN) from the public Pokémon
  TCG listing of the REBEL wholesaler (hurt.rebel.pl) into
  `TcgCheap.Sealed.SuggestedPrice` and matches them to catalogue products.

  The listing gives REBEL's product id, name and SCD; an item's barcode is
  read once from its product page. The host asks for 5 seconds between
  requests (robots.txt `Crawl-delay`), so the first run reads about fifty
  product pages in a few minutes and later runs only the listing and new
  items. A listing that fails or has no items writes nothing; a product page
  that fails leaves the barcode for the next run.

  Matching is `TcgCheap.Sealed.Matcher` against English products (REBEL
  sells English editions), reading REBEL's "Booster Display (36)" as
  Cardmarket's "Booster Box". Other items sold as several units ("Tin Bundle
  (6)") are matched only when named a display, as Cardmarket names them, so
  the price of several units never lands on a single one. Only products
  Cardmarket added at most two years before REBEL first listed the item are
  candidates: REBEL names a reprint without its year ("Battle Academy").
  """

  require Logger

  alias TcgCheap.Sealed
  alias TcgCheap.Sealed.{Ean, HtmlListing, Matcher, ShopFeed, SuggestedPrice}

  @base "https://hurt.rebel.pl"
  @listing "/search/pokemon-tcg.html"
  @pause_ms 5_000
  @max_pages 10
  @reprint_window_days 2 * 365

  @type item :: %{
          rebel_id: String.t(),
          title: String.t(),
          url: String.t(),
          price: Decimal.t()
        }

  @doc """
  Reads the listing, stores every item and re-matches. `req_options` are
  merged into each request.
  """
  @spec run(keyword()) ::
          {:ok, %{items: non_neg_integer(), matched: non_neg_integer()}} | {:error, term()}
  def run(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    req_options = Keyword.get(opts, :req_options, [])
    known = Map.new(Sealed.list_suggested_prices!(), &{&1.rebel_id, &1.ean})

    with {:ok, items} <- listing(1, [], req_options) do
      items
      |> Enum.map(
        &Map.merge(&1, %{ean: known[&1.rebel_id] || ean(&1, req_options), last_seen_at: now})
      )
      |> record()

      {:ok, %{items: length(items), matched: rematch()}}
    end
  end

  @doc """
  Matches every item without a manual decision again (the catalogue and the
  known barcodes change) and returns how many items have a product.
  """
  @spec rematch() :: non_neg_integer()
  def rematch do
    english = Enum.filter(Sealed.list_products!(), &(&1.region == :en))
    eans = Sealed.known_eans()

    Sealed.list_suggested_prices!()
    |> Enum.group_by(&DateTime.to_date(&1.inserted_at))
    |> Enum.map(fn {listed_on, items} ->
      index = english |> Enum.filter(&candidate?(&1, listed_on)) |> Matcher.index(eans)
      Enum.count(items, &rematch(&1, index))
    end)
    |> Enum.sum()
  end

  defp rematch(%SuggestedPrice{manual?: true} = item, _index), do: item.product_id

  defp rematch(item, index) do
    id = product_id(item, index)
    if id != item.product_id, do: Sealed.match_suggested_price!(item, id)
    id
  end

  defp candidate?(%{cardmarket_added_on: nil}, _listed_on), do: true

  defp candidate?(%{cardmarket_added_on: added_on}, listed_on),
    do: Date.diff(listed_on, added_on) <= @reprint_window_days

  @doc "The product an item matches automatically, or nil."
  @spec product_id(map(), Matcher.t()) :: Ecto.UUID.t() | nil
  def product_id(item, index) do
    title = String.replace(item.title, ~r/Booster Display \(36\)/i, "Booster Box")

    if several_units?(title),
      do: nil,
      else: Matcher.product_id(%{title: title, ean: item.ean}, index)
  end

  defp several_units?(title) do
    case Regex.run(~r/\((\d+)\)/, title) do
      [_, count] -> String.to_integer(count) > 1 and not (title =~ ~r/display/i)
      nil -> false
    end
  end

  defp record(items) do
    %Ash.BulkResult{status: :success} =
      Ash.bulk_create!(items, SuggestedPrice, :record,
        domain: Sealed,
        return_errors?: true,
        stop_on_error?: true
      )
  end

  defp listing(number, acc, req_options) do
    with {:ok, document} <- get(@listing, [page: number], req_options),
         {:ok, items} <- items(document) do
      last = last_page(document)

      cond do
        last > @max_pages -> {:error, :too_many_pages}
        number < last -> listing(number + 1, acc ++ items, req_options)
        true -> {:ok, Enum.uniq_by(acc ++ items, & &1.rebel_id)}
      end
    end
  end

  defp items(document) do
    rows = Floki.find(document, "tr.product-row")
    items = Enum.flat_map(rows, &item/1)

    if length(items) < length(rows),
      do: Logger.warning("REBEL: skipped #{length(rows) - length(items)} unreadable rows")

    if items == [], do: {:error, :no_items}, else: {:ok, items}
  end

  defp item(row) do
    link = HtmlListing.first(row, "strong[itemprop=name] a")

    path =
      link && link |> Floki.attribute("href") |> List.first("") |> URI.parse() |> Map.get(:path)

    with [_, id] <- Regex.run(~r/\Aproduct-row product-(\d{1,20})\b/, class(row)),
         true <- is_binary(path) and path =~ ~r{\A/products/[a-z0-9-]+\.html\z},
         {:ok, title} <- ShopFeed.title(HtmlListing.text(link)),
         {:ok, price} <- row |> Floki.find("td") |> List.last() |> HtmlListing.text() |> price() do
      [%{rebel_id: id, title: title, url: @base <> path, price: price}]
    else
      _ -> []
    end
  end

  defp class(row), do: row |> Floki.attribute("class") |> List.first("")

  defp price(text) do
    with {:ok, decimal} <- HtmlListing.price_text(text), do: ShopFeed.decimal_price(decimal)
  end

  defp last_page(document) do
    for(
      page <- Floki.attribute(document, "a.page-link", "data-page"),
      {n, ""} <- [Integer.parse(page)],
      do: n
    )
    |> Enum.max(fn -> 1 end)
  end

  defp ean(%{url: @base <> path}, req_options) do
    case get(path, [], req_options) do
      {:ok, document} ->
        document |> HtmlListing.first("[itemprop=gtin13]") |> HtmlListing.text() |> barcode()

      {:error, reason} ->
        Logger.warning("REBEL: no barcode for #{path}: #{inspect(reason)}")
        nil
    end
  end

  # The text reads "( EAN-13: 196214144828 )"; the code is the long number.
  defp barcode(nil), do: nil

  defp barcode(text) do
    case Regex.run(~r/\b\d{12,13}\b/, text) do
      [code] -> Ean.normalize(code)
      nil -> nil
    end
  end

  defp get(path, params, req_options) do
    Process.sleep(@pause_ms)

    request =
      Req.new(
        url: @base <> path,
        params: params,
        headers: [{"user-agent", "TcgCheap/1.0 (buying guide)"}],
        decode_body: false,
        connect_options: [timeout: 5_000],
        receive_timeout: 15_000,
        redirect: false,
        retry: false
      )
      |> Req.merge(req_options)

    case Req.request(request) do
      {:ok, %Req.Response{status: 200} = response} -> ShopFeed.html(response)
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, {:transport, exception.__struct__}}
    end
  end
end
