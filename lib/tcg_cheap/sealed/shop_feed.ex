defmodule TcgCheap.Sealed.ShopFeed do
  @moduledoc """
  The contract of a shop feed client and the hardening every client shares.

  A shop's `source` is the client module that reads its feed
  (`TcgCheap.Sealed.ShopFeed.WooCommerce`, `TcgCheap.Sealed.ShopFeed.Shopify`,
  `TcgCheap.Sealed.ShopFeed.GoogleFeed`, `TcgCheap.Sealed.ShopFeed.CeneoFeed`,
  `TcgCheap.Sealed.ShopFeed.IdoSell`, `TcgCheap.Sealed.ShopFeed.PrestaShop`, and the readers of
  HTML listings, mostly built on `TcgCheap.Sealed.ShopFeed.HtmlListing`); a new kind
  of feed is one more module implementing this behaviour.

  Requests go only to the shop's fixed HTTPS host (its `feed_host`, when
  set), one at a time with a short pause before each (several shops refuse
  quick successive requests; a client may ask for a longer one, and so may
  the host's robots.txt `Crawl-delay`), follow no redirects and read at most
  5 MB per page, or more where a client asks for it (a whole-shop XML export).
  Every request is the bot's (`TcgCheap.Bot`): it carries the bot's User-Agent
  and Web Bot Auth signature, and it is made only where the host's robots.txt
  allows. A policy reason (a path robots.txt disallows, a 401, a 403 or a
  challenge, a `Retry-After` longer than the wait a client allows) ends the
  whole fetch at once, optional requests included, and is returned as the
  fetch's error; `TcgCheap.Sealed.FetchWorker` does not retry it at once. A
  rate-limited (429) or unavailable (503) request with a short `Retry-After`
  is repeated once after it; with no `Retry-After` a 429 is repeated after
  10 s and then fails, and `TcgCheap.Sealed.FetchWorker` retries it minutes
  later. A fetch run by that
  worker passes a `:journal` in its `req_options` (`TcgCheap.Sealed.FetchJournal`),
  which keeps the responses already read so that a restarted fetch does not
  read them again. Every product field
  is untrusted: products with an invalid id, title, URL, price or availability
  are skipped and counted in a warning. Any transport, status, pagination or
  shape problem fails the whole fetch so that
  a partial catalogue is never mistaken for a complete one.
  """

  require Logger

  alias TcgCheap.Bot
  alias TcgCheap.Sealed.{FetchJournal, Matcher, Shop}

  @request_pause_ms 1_000
  # Kept short by default: a wait holds up the shops queued behind this one,
  # and the job must stay within its 5-minute timeout.
  @max_retry_after_ms 10_000
  @max_body_bytes 5_000_000
  @max_title_length 300
  @max_url_length 2_000
  @product_id ~r/\A[A-Za-z0-9_-]{1,40}\z/
  @decimal_price ~r/\A[0-9]{1,9}(?:\.[0-9]{1,2})?\z/
  @spaces ~r/\s+/u
  @entity ~r/&(#x[0-9a-f]{1,6}|#[0-9]{1,7}|[a-z]{2,8});/i
  @https_url ~r/\Ahttps:\/\/[^\s]+\z/
  # Shops list products they cannot price yet (pre-orders) at a token 0.01 zł;
  # no sealed product costs under 1 zł, so a lower price is no price.
  @min_price Decimal.new(1)

  # A pre-order is never in stock; feeds that cannot tell leave `preorder` out.
  # `market_prices`: what the offer costs buyers of other countries, by
  # country, where the shop prices them apart (`Shop.deliveries`).
  @type offer :: %{
          optional(:preorder) => boolean(),
          optional(:kind) => :single | :sealed,
          optional(:category) => String.t() | nil,
          optional(:market_prices) => %{
            String.t() => %{price: Decimal.t(), currency: String.t()}
          },
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

  @doc """
  The hosts the shop's product images may be shown from; a client states them
  only when they are not just the shop's own host (see `image_hosts/1`).
  """
  @callback image_hosts(Shop.t()) :: [String.t()]

  @optional_callbacks image_hosts: 1

  @doc """
  The hosts the shop's product images may be shown from: those its client
  states, else the shop's own host.
  """
  @spec image_hosts(Shop.t()) :: [String.t()]
  def image_hosts(%Shop{source: source, host: host} = shop) do
    Code.ensure_loaded(source)
    if function_exported?(source, :image_hosts, 1), do: source.image_hosts(shop), else: [host]
  end

  @doc """
  GETs `path` on the shop's host (or `feed_host`), a pause
  (`pause_ms`, default #{@request_pause_ms} ms, or the host's `Crawl-delay` when that is longer)
  after the host's last request, and
  returns the 200 response with its raw body, at
  most `max_body_bytes` long (default 5 MB), over the HTTP `protocols` given
  (default HTTP/1.1). A 429 or 503 is retried after a `Retry-After` of at most
  `max_retry_after_ms` (default #{@max_retry_after_ms} ms). A response the fetch's
  journal holds is returned without a request or a pause. With `optional: true`
  (a request the fetch can do without) the journal also keeps a failure, so the
  request is not made again in the same fetch.
  """
  @spec get(Shop.t(), String.t(), keyword(), keyword(), [
          {:max_body_bytes, pos_integer()}
          | {:max_retry_after_ms, pos_integer()}
          | {:optional, boolean()}
          | {:pause_ms, pos_integer()}
          | {:protocols, [:http1 | :http2]}
        ]) ::
          {:ok, Req.Response.t()} | {:error, term()}
  def get(%Shop{} = shop, path, params, req_options, opts \\ []) do
    {journal, req_options} = Keyword.pop(req_options, :journal)
    {optional, opts} = Keyword.pop(opts, :optional, false)

    case FetchJournal.through(
           journal,
           path,
           params,
           fn -> request(shop, path, params, req_options, opts) end,
           optional: optional
         ) do
      {:ok, %Req.Response{} = response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  # A reason the bot's policy ends the shop's fetch with (`TcgCheap.Bot`) leaves
  # the client at once, optional requests included: the shop is not asked again.
  defp request(shop, path, params, req_options, opts) do
    host = shop.feed_host || shop.host
    max_body_bytes = Keyword.get(opts, :max_body_bytes, @max_body_bytes)
    max_retry_after_ms = Keyword.get(opts, :max_retry_after_ms, @max_retry_after_ms)
    pause_ms = Keyword.get(opts, :pause_ms, @request_pause_ms)
    protocols = Keyword.get(opts, :protocols, [:http1])

    # The URL that is requested is the one robots.txt is asked about.
    {url, target} = Bot.request_url(host, path, params)

    request =
      [
        url: url,
        decode_body: false,
        into: &bounded_body(&1, &2, max_body_bytes),
        connect_options: [timeout: 5_000, protocols: protocols],
        receive_timeout: 15_000,
        redirect: false,
        retry: Bot.retry_step(max_retry_after_ms),
        max_retries: 1
      ]
      |> Bot.new()
      |> Req.merge(req_options)

    # Waits for the host's turn: the larger of the shop's `Crawl-delay` and the
    # client's own pause after the request before it, whoever made that.
    with {:error, reason} <-
           Bot.permit(host, target, req_options,
             pause_ms: pause_ms,
             protocols: protocols,
             max_retry_after_ms: max_retry_after_ms
           ),
         do: Bot.stop(reason)

    case Req.request(request) do
      {:ok, response} -> answer(host, response)
      {:error, exception} -> {:error, {:transport, exception.__struct__}}
    end
  end

  defp answer(host, response) do
    case Bot.classify(host, response) do
      {:stop, reason} -> Bot.stop(reason)
      :ok -> status(response)
    end
  end

  defp status(%Req.Response{status: 200, body: :too_large}), do: {:error, :response_too_large}
  defp status(%Req.Response{status: 200} = response), do: {:ok, response}
  defp status(%Req.Response{status: status}), do: {:error, {:http_status, status}}

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
  # "Pokemony", "Pokemonów" in Polish category names count too, and "PKM", the
  # abbreviation some Portuguese shops put in front of their titles.
  defp pokemon?(text),
    do:
      text
      |> Matcher.normalize()
      |> String.split()
      |> Enum.any?(&(&1 == "pkm" or String.starts_with?(&1, "pokemon")))

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

  @doc """
  A price above the token-price minimum, in the shop's currency. Refresh
  checks the upper limit after conversion to PLN, for every feed client.
  """
  @spec price(Decimal.t()) :: {:ok, Decimal.t()} | :error
  def price(price, kind \\ :sealed)

  def price(%Decimal{} = price, kind) do
    # Bulk commons legitimately cost 0.50 zł; 0.01 zł remains a token price.
    minimum = if kind == :single, do: Decimal.new("0.10"), else: @min_price

    if Decimal.lt?(price, minimum), do: :error, else: {:ok, price}
  end
end
