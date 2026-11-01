defmodule TcgCheap.Sealed.HtmlListing do
  @moduledoc """
  What the clients that read category pages (`TcgCheap.Sealed.ShopGold`,
  `Sellingo`, `Selly`, `Sote`) share: fetching and parsing one page politely,
  reading a node's text, and walking a shop's `listing_paths`.

  Pages of one shop are requested one after another with a short pause, so a
  shop with many pages is never hit in bursts.
  """

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @page_pause_ms 1_000

  @doc """
  Fetches and parses the page at `path`. `index` counts the shop's requests
  so far: every request after the first waits `#{@page_pause_ms}` ms.
  """
  @spec page(Shop.t(), String.t(), keyword(), non_neg_integer()) ::
          {:ok, Floki.html_tree()} | {:error, term()}
  def page(shop, path, req_options, index) do
    if index > 0, do: Process.sleep(@page_pause_ms)

    with {:ok, response} <- ShopFeed.get(shop, path, [], req_options) do
      case Floki.parse_document(response.body) do
        {:ok, document} -> {:ok, document}
        {:error, _reason} -> {:error, :malformed_response}
      end
    end
  end

  @doc """
  Runs `read` (path -> `{:ok, products}` | `{:error, reason}`) on each of the
  shop's listing paths, pausing between listings, and joins the products. Any
  failing listing fails the fetch.
  """
  @spec read_listings(Shop.t(), (String.t() -> {:ok, [map()]} | {:error, term()})) ::
          {:ok, [map()]} | {:error, term()}
  def read_listings(%Shop{listing_paths: [_ | _] = paths}, read) do
    paths
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {path, index}, {:ok, acc} ->
      if index > 0, do: Process.sleep(@page_pause_ms)

      case read.(path) do
        {:ok, products} -> {:cont, {:ok, acc ++ products}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "The text of a node (or the first of a list), whitespace collapsed; nil when empty."
  @spec text(Floki.html_tree() | Floki.html_node() | nil) :: String.t() | nil
  def text(nil), do: nil

  def text(node) do
    case node |> Floki.text(sep: " ") |> String.replace(~r/[\s\x{a0}]+/u, " ") |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  @doc "The first node matching `selector`, or nil."
  @spec first(Floki.html_tree() | Floki.html_node(), String.t()) :: Floki.html_node() | nil
  def first(node, selector), do: node |> Floki.find(selector) |> List.first()

  @doc "The first value of attribute `name` on nodes matching `selector`, or nil."
  @spec attr(Floki.html_tree() | Floki.html_node(), String.t(), String.t()) :: String.t() | nil
  def attr(node, selector, name), do: node |> Floki.attribute(selector, name) |> List.first()

  @doc """
  A price written in Polish style (`"1 369,99 zł"`, `"280,00 zł."`, `"89,90"`)
  or with a decimal point (`"25.00 zł"`), with an optional `zł`/`PLN`
  suffix, as a decimal string `ShopFeed.decimal_price/1` accepts.
  """
  @spec price_text(String.t() | nil) :: {:ok, String.t()} | :error
  def price_text(nil), do: :error

  def price_text(text) do
    squeezed = String.replace(text, ~r/[\s\x{a0}]+/u, "")

    case Regex.run(~r/\A([0-9]{1,7})(?:[,.]([0-9]{1,2}))?(?:zł|PLN)?\.?\z/u, squeezed) do
      [_, whole] -> {:ok, whole}
      [_, whole, cents] -> {:ok, whole <> "." <> cents}
      nil -> :error
    end
  end
end
