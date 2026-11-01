defmodule TcgCheap.Sealed.HtmlListing do
  @moduledoc """
  What the clients that read category pages (`TcgCheap.Sealed.ShopGold`,
  `Sellingo`, `Selly`, `Sote`) share: fetching and parsing one page, reading
  a node's text and price, and walking a shop's `listing_paths`.
  """

  alias TcgCheap.Sealed.{Shop, ShopFeed}

  @doc "Fetches and parses the page at `path`."
  @spec page(Shop.t(), String.t(), keyword()) :: {:ok, Floki.html_tree()} | {:error, term()}
  def page(shop, path, req_options) do
    with {:ok, response} <- ShopFeed.get(shop, path, [], req_options),
         do: ShopFeed.html(response)
  end

  @doc """
  Runs `read` (path -> `{:ok, products}` | `{:error, reason}`) on each of the
  shop's listing paths and joins the products. Any
  failing listing fails the fetch.
  """
  @spec read_listings(Shop.t(), (String.t() -> {:ok, [map()]} | {:error, term()})) ::
          {:ok, [map()]} | {:error, term()}
  def read_listings(%Shop{listing_paths: [_ | _] = paths}, read) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
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
