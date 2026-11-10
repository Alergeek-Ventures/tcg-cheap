defmodule TcgCheap.Sealed.ShopFeed do
  @moduledoc """
  The contract of a shop feed client and the hardening every client shares.

  A shop's `source` is the client module that reads its feed
  (`TcgCheap.Sealed.WooCommerce`, `TcgCheap.Sealed.Shopify`,
  `TcgCheap.Sealed.GoogleFeed`, `TcgCheap.Sealed.CeneoFeed`,
  `TcgCheap.Sealed.IdoSell`, `TcgCheap.Sealed.PrestaShop`, and the readers of
  HTML listings, mostly built on `TcgCheap.Sealed.HtmlListing`); a new kind
  of feed is one more module implementing this behaviour.

  Requests go only to the shop's fixed HTTPS host (its `feed_host`, when
  set), one at a time with a short pause before each (several shops refuse
  quick successive requests; a client may ask for a longer one), follow no redirects and read at most 5 MB per
  page, or more where a client asks for it (a whole-shop XML export). A
  rate-limited request (429) is repeated once after the shop's `Retry-After`
  when that is short; otherwise the fetch fails and
  `TcgCheap.Sealed.FetchWorker` retries it minutes later. Every product field
  is untrusted: products with an invalid id, title, URL, price or availability
  are skipped and counted in a warning. Any transport, status, pagination or
  shape problem fails the whole fetch so that
  a partial catalogue is never mistaken for a complete one.
  """

  require Logger

  alias TcgCheap.Sealed.{Matcher, Shop}

  @request_pause_ms 1_000
  # Kept short: a Shopify fetch may wait once per request (up to 7 requests),
  # and the job must stay within its 5-minute timeout.
  @rate_limit_delay_ms 10_000
  @max_retry_after_ms 10_000
  @max_body_bytes 5_000_000
  @max_title_length 300
  @max_url_length 2_000
  @product_id ~r/\A[A-Za-z0-9_-]{1,40}\z/
  @decimal_price ~r/\A[0-9]{1,7}(?:\.[0-9]{1,2})?\z/
  @spaces ~r/\s+/u
  @entity ~r/&(#x[0-9a-f]{1,6}|#[0-9]{1,7}|[a-z]{2,8});/i
  @https_url ~r/\Ahttps:\/\/[^\s]+\z/
  # Shops list products they cannot price yet (pre-orders) at a token 0.01 zł;
  # no sealed product costs under 1 zł, so a lower price is no price.
  @min_price Decimal.new(1)
  @max_price Decimal.new(1_000_000)

  # A pre-order is never in stock; feeds that cannot tell leave `preorder` out.
  @type offer :: %{
          optional(:preorder) => boolean(),
          optional(:kind) => :single | :sealed,
          optional(:category) => String.t() | nil,
          shop_product_id: String.t(),
          title: String.t(),
          url: String.t(),
          image_url: String.t() | nil,
          ean: String.t() | nil,
          price: Decimal.t(),
          in_stock: boolean()
        }

  @doc """
  Fetches every sealed product and configured single the shop currently lists. `req_options` are
  merged into each request (a `Req.Test` plug, for instance). A client that
  reads singles with requests of their own answers `{:partial, offers,
  reason}` when only those failed, so the sealed offers are still stored
  (`with_singles/3`).
  """
  @callback fetch(Shop.t(), req_options :: keyword()) ::
              {:ok, [offer()]} | {:partial, [offer()], term()} | {:error, term()}

  @doc "The hosts the shop's product images may be shown from."
  @callback image_hosts(Shop.t()) :: [String.t()]

  @doc """
  GETs `path` on the shop's host (or `feed_host`), after a pause
  (`pause_ms`, default #{@request_pause_ms} ms), and returns the 200 response with its raw body, at
  most `max_body_bytes` long (default 5 MB), over the HTTP `protocols` given
  (default HTTP/1.1).
  """
  @spec get(Shop.t(), String.t(), keyword(), keyword(), [
          {:max_body_bytes, pos_integer()}
          | {:pause_ms, pos_integer()}
          | {:protocols, [:http1 | :http2]}
        ]) ::
          {:ok, Req.Response.t()} | {:error, term()}
  def get(%Shop{} = shop, path, params, req_options, opts \\ []) do
    host = shop.feed_host || shop.host
    max_body_bytes = Keyword.get(opts, :max_body_bytes, @max_body_bytes)

    request =
      Req.new(
        url: "https://#{host}#{path}",
        params: params,
        headers: [{"user-agent", "TcgCheap/1.0 (buying guide)"}],
        decode_body: false,
        into: &bounded_body(&1, &2, max_body_bytes),
        connect_options: [timeout: 5_000, protocols: Keyword.get(opts, :protocols, [:http1])],
        receive_timeout: 15_000,
        redirect: false,
        retry: &retry_rate_limited/2,
        max_retries: 1
      )
      |> Req.merge(req_options)

    Process.sleep(Keyword.get(opts, :pause_ms, @request_pause_ms))

    case Req.request(request) do
      {:ok, %Req.Response{status: 200, body: :too_large}} -> {:error, :response_too_large}
      {:ok, %Req.Response{status: 200} = response} -> {:ok, response}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, {:transport, exception.__struct__}}
    end
  end

  # Waits in the job only when the shop asks for a short pause (or names
  # none); a longer one would hold up the shops queued behind it.
  defp retry_rate_limited(_request, %Req.Response{status: 429} = response) do
    case retry_after(response) do
      nil -> {:delay, @rate_limit_delay_ms}
      delay when delay <= @max_retry_after_ms -> {:delay, delay}
      _long -> false
    end
  end

  defp retry_rate_limited(_request, _response_or_exception), do: false

  defp retry_after(response) do
    Req.Response.get_retry_after(response)
  rescue
    # An unparsable HTTP date; the header is the shop's, not ours.
    ArgumentError -> nil
  end

  defp bounded_body({:data, data}, {request, response}, max_body_bytes) do
    body = if is_binary(response.body), do: response.body, else: ""

    if byte_size(body) + byte_size(data) > max_body_bytes,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: body <> data}}}
  end

  @doc """
  Parses an HTML response body (UTF-8) into a Floki document. A body some
  shops gzip even though `get/5` returns it raw is unzipped first, to at most
  the page size limit.
  """
  @spec html(Req.Response.t()) :: {:ok, Floki.html_tree()} | {:error, :malformed_response}
  def html(%Req.Response{body: body} = response) when is_binary(body) do
    with {:ok, body} <- gunzip(body, Req.Response.get_header(response, "content-encoding")),
         true <- String.valid?(body),
         {:ok, document} <- Floki.parse_document(body) do
      {:ok, document}
    else
      _ -> {:error, :malformed_response}
    end
  end

  defp gunzip(body, ["gzip"]) do
    zlib = :zlib.open()

    try do
      # 16 + 15: a gzip wrapper around the largest deflate window.
      :ok = :zlib.inflateInit(zlib, 31)
      inflate(zlib, :zlib.safeInflate(zlib, body), [], 0)
    rescue
      ErlangError -> :error
    after
      :zlib.close(zlib)
    end
  end

  defp gunzip(body, _encoding), do: {:ok, body}

  # Inflates chunk by chunk so a small body cannot expand past the limit.
  defp inflate(zlib, {status, chunk}, acc, size) do
    size = size + IO.iodata_length(chunk)

    cond do
      size > @max_body_bytes -> :error
      status == :finished -> finish(zlib, [chunk | acc])
      true -> inflate(zlib, :zlib.safeInflate(zlib, []), [chunk | acc], size)
    end
  end

  defp inflate(_zlib, _need_dictionary, _acc, _size), do: :error

  # A truncated body also ends as `:finished`; only `inflateEnd` notices.
  defp finish(zlib, chunks) do
    :ok = :zlib.inflateEnd(zlib)
    {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  @doc "Decodes a JSON response body."
  @spec decode(Req.Response.t()) :: {:ok, term()} | {:error, :malformed_response}
  def decode(%Req.Response{body: body}) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, %Jason.DecodeError{}} -> {:error, :malformed_response}
    end
  end

  @doc """
  Turns feed products into unique offers with `normalize`, which returns
  `{:ok, offers}` (one product may list several), `:ignore` (not a sealed
  product) or `:invalid` (counted and logged).
  """
  @spec offers(Shop.t(), [term()], (term() -> {:ok, [offer()]} | :ignore | :invalid)) ::
          [offer()]
  def offers(shop, products, normalize) do
    {offers, skipped} =
      Enum.reduce(products, {[], 0}, fn product, {offers, skipped} ->
        case normalize.(product) do
          {:ok, new} -> {Enum.reverse(new, offers), skipped}
          :ignore -> {offers, skipped}
          :invalid -> {offers, skipped + 1}
        end
      end)

    if skipped > 0,
      do: Logger.warning("sealed fetch #{shop.key}: skipped #{skipped} invalid products")

    offers |> Enum.reverse() |> Enum.uniq_by(& &1.shop_product_id)
  end

  @doc """
  The result of a fetch whose singles (`{:single, product}`) were read apart
  from its sealed `products`: all offers made with `to_offers`, or, when the
  singles failed, `{:partial, offers, reason}` with the sealed ones alone.
  """
  @spec with_singles([term()], {:ok, [term()]} | {:error, term()}, ([term()] -> [offer()])) ::
          {:ok, [offer()]} | {:partial, [offer()], term()}
  def with_singles(products, {:ok, singles}, to_offers),
    do: {:ok, to_offers.(products ++ singles)}

  def with_singles(products, {:error, reason}, to_offers),
    do: {:partial, to_offers.(products), reason}

  @doc """
  Whether a product of a mixed listing is sealed Pokémon: its title names a
  sealed product (`TcgCheap.Sealed.Matcher.sealed_title?/1`) and its title or
  the shop's category for it (nil when unknown) says Pokémon.
  """
  @spec sealed_pokemon?(String.t(), String.t() | nil) :: boolean()
  def sealed_pokemon?(title, category) do
    Matcher.sealed_title?(title) and (pokemon?(title) or pokemon?(category))
  end

  @doc "Category prefixes take precedence over the sealed title rule."
  def single?(%Shop{singles_categories: prefixes}, category)
      when is_list(prefixes) and is_binary(category),
      do: Enum.any?(prefixes, &String.starts_with?(category, &1))

  def single?(_shop, _category), do: false

  defp pokemon?(nil), do: false
  # "Pokemony", "Pokemonów" in Polish category names count too.
  defp pokemon?(text),
    do:
      text
      |> Matcher.normalize()
      |> String.split()
      |> Enum.any?(&String.starts_with?(&1, "pokemon"))

  @doc "A shop's own product id: 1–40 letters, digits, `_` or `-`."
  @spec product_id(term()) :: {:ok, String.t()} | :error
  def product_id(id) when is_binary(id) do
    if Regex.match?(@product_id, id), do: {:ok, id}, else: :error
  end

  def product_id(_id), do: :error

  @doc """
  A price written as a plain decimal (`"12"`, `"18.5"`, `"139.95"`), within
  the limits of `price/1`.
  """
  @spec decimal_price(term()) :: {:ok, Decimal.t()} | :error
  def decimal_price(value, kind \\ :sealed)

  def decimal_price(value, kind) when is_binary(value) do
    if Regex.match?(@decimal_price, value),
      do: price(Decimal.new(value), kind),
      else: :error
  end

  def decimal_price(_value, _kind), do: :error

  @doc "A product title with HTML entities decoded and whitespace collapsed."
  @spec title(term()) :: {:ok, String.t()} | :error
  def title(name) when is_binary(name) do
    title = name |> html_decode() |> String.replace(@spaces, " ") |> String.trim()

    if String.valid?(title) and String.length(title) in 1..@max_title_length,
      do: {:ok, title},
      else: :error
  end

  def title(_name), do: :error

  @entities %{
    "amp" => "&",
    "quot" => "\"",
    "apos" => "'",
    "lt" => "<",
    "gt" => ">",
    "nbsp" => " ",
    "ndash" => "–",
    "mdash" => "—",
    "rsquo" => "’",
    "lsquo" => "‘",
    "rdquo" => "”",
    "ldquo" => "“",
    "bdquo" => "„",
    "hellip" => "…"
  }

  defp html_decode(value) do
    Regex.replace(@entity, value, fn entity, code ->
      decode_entity(entity, code)
    end)
  end

  defp decode_entity(entity, "#x" <> hex), do: codepoint(entity, Integer.parse(hex, 16))
  defp decode_entity(entity, "#X" <> hex), do: codepoint(entity, Integer.parse(hex, 16))
  defp decode_entity(entity, "#" <> dec), do: codepoint(entity, Integer.parse(dec))
  defp decode_entity(entity, name), do: Map.get(@entities, String.downcase(name), entity)

  defp codepoint(_entity, {value, ""}) when value in 0x20..0xD7FF or value in 0xE000..0x10FFFF,
    do: <<value::utf8>>

  defp codepoint(entity, _parsed), do: entity

  @doc """
  Parses an absolute `https://` URL on one of `hosts` (default port, no
  credentials, fragment or whitespace).
  """
  @spec https_url(term(), [String.t()]) :: {:ok, URI.t()} | :error
  def https_url(url, hosts) when is_binary(url) and byte_size(url) <= @max_url_length do
    uri = URI.parse(url)

    if uri.scheme == "https" and uri.host in hosts and uri.port == 443 and
         is_nil(uri.userinfo) and is_nil(uri.fragment) and is_binary(uri.path) and
         String.match?(url, @https_url),
       do: {:ok, uri},
       else: :error
  end

  def https_url(_url, _hosts), do: :error

  @doc "An image URL on one of `hosts`, or nil."
  @spec image_url(term(), [String.t()]) :: String.t() | nil
  def image_url(url, hosts) do
    case https_url(url, hosts) do
      {:ok, _uri} -> url
      :error -> nil
    end
  end

  @doc "A price from 1 zł to 1 000 000 zł."
  @spec price(Decimal.t()) :: {:ok, Decimal.t()} | :error
  def price(price, kind \\ :sealed)

  def price(%Decimal{} = price, kind) do
    # Bulk commons legitimately cost 0.50 zł; 0.01 zł remains a token price.
    minimum = if kind == :single, do: Decimal.new("0.10"), else: @min_price

    if not Decimal.lt?(price, minimum) and not Decimal.gt?(price, @max_price),
      do: {:ok, price},
      else: :error
  end
end
