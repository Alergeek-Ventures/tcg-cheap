defmodule TcgCheap.Storage.ImageDownload do
  @moduledoc "Bounded downloads of allowlisted raster images for background mirroring, and their trimming."

  alias TcgCheap.Bot
  alias TcgCheap.Bot.Hosts
  alias TcgCheap.Sealed.ExternalImage

  @max_bytes 15 * 1024 * 1024
  @max_pixels 40_000_000
  @deadline_ms 8_000
  # A host that refused an image is not asked for another for this long: the
  # time of a mirror run, not of a night.
  @refusal_ms :timer.hours(1)
  # A redirect waits for its turn inside the download's deadline.
  @redirect_wait_ms 3_000

  # Object storage that answers 403, not 404, for a key it does not have: a 403
  # there says nothing about the host.
  @missing_as_403 ["limitlesstcg.nyc3.cdn.digitaloceanspaces.com"]

  @doc "Hosts whose object storage answers 403 for a missing image."
  @spec missing_as_403_hosts() :: [String.t()]
  def missing_as_403_hosts, do: @missing_as_403

  @doc """
  Downloads an allowlisted remote image as the bot (`TcgCheap.Bot`): only
  where the host's robots.txt allows the path (also that of a redirect it
  follows), spaced by its pause or `Crawl-delay`, and without a second try at
  a host that refused us (a 401, a 403 or a challenge) or asked to be left
  alone: a host that refused an image is not asked for another for an hour.
  """
  @spec fetch(term(), keyword()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch(url, req_options \\ []) do
    if ExternalImage.valid?(url),
      do: fetch_allowed(request_url(url), req_options),
      else: {:error, :host_not_allowed}
  end

  defp fetch_allowed(url, req_options) do
    %URI{host: host} = uri = URI.parse(url)

    with :ok <- not_refused(host),
         :ok <- Bot.permit(host, Bot.target(uri), req_options) do
      download(url, host, req_options, true)
    end
  end

  defp not_refused(host) do
    case Hosts.image_refusal(String.downcase(host)) do
      {refusal, until} -> if Hosts.now() < until, do: {:error, {:refused, refusal}}, else: :ok
      nil -> :ok
    end
  end

  # Shops publish photo URLs with raw characters a request target may not
  # hold, such as an en dash in a WordPress file name; browsers
  # percent-encode them, while Req refuses the request ("invalid request
  # target"). Encode them the same way, keeping the escapes already there.
  defp request_url(url), do: URI.encode(url, &(URI.char_unescaped?(&1) or &1 == ?%))

  @doc """
  Cuts the transparent margins logos and packshots often pad their subject
  with, which would show it smaller than a tight image. An image with no alpha
  band or nothing to cut stays as downloaded.
  """
  @spec trim_transparent_margins(binary(), String.t()) :: {:ok, binary(), String.t()}
  def trim_transparent_margins(body, type) do
    with {:ok, image} <- Image.from_binary(body),
         {:ok, trimmed} <- Image.trim(image, background: :alpha),
         {:ok, png} <- Image.write(trimmed, :memory, suffix: ".png") do
      {:ok, png, "image/png"}
    else
      _error -> {:ok, body, type}
    end
  end

  @doc """
  Splits the crop off a photo URL ending in `#crop=left,top,width,height`
  (percentages of the image), for an item shown in a picture of several
  things: the URL to download and the crop, `nil` without one, or `:invalid`.
  """
  @spec split_crop(String.t()) ::
          {String.t(), {number(), number(), number(), number()} | :invalid | nil}
  def split_crop(url) do
    case String.split(url, "#crop=", parts: 2) do
      [source, crop] -> {source, parse_crop(crop)}
      [source] -> {source, nil}
    end
  end

  defp parse_crop(crop) do
    with [_ | _] = parts <- String.split(crop, ","),
         [left, top, width, height] <- Enum.map(parts, &percent/1),
         true <- Enum.all?([left, top, width, height], &is_number/1),
         true <- width > 0 and height > 0 and left + width <= 100 and top + height <= 100 do
      {left, top, width, height}
    else
      _invalid -> :invalid
    end
  end

  defp percent(value) do
    case Float.parse(value) do
      {number, ""} when number >= 0 and number <= 100 -> number
      _invalid -> nil
    end
  end

  @doc "Cuts a crop from `split_crop/1` out of a downloaded image, as PNG."
  @spec crop(binary(), String.t(), {number(), number(), number(), number()} | :invalid | nil) ::
          {:ok, binary(), String.t()} | {:error, term()}
  def crop(body, type, nil), do: {:ok, body, type}
  def crop(_body, _type, :invalid), do: {:error, :invalid_crop}

  def crop(body, _type, crop) do
    with {:ok, image} <- Image.from_binary(body),
         {left, top, width, height} = pixels(crop, Image.width(image), Image.height(image)),
         {:ok, cropped} <- Image.crop(image, left, top, width, height),
         {:ok, png} <- Image.write(cropped, :memory, suffix: ".png") do
      {:ok, png, "image/png"}
    end
  end

  # Percentages to whole pixels inside the image, at least one wide.
  defp pixels({left, top, width, height}, image_width, image_height) do
    left = min(round(left * image_width / 100), image_width - 1)
    top = min(round(top * image_height / 100), image_height - 1)

    {left, top, max(1, min(round(width * image_width / 100), image_width - left)),
     max(1, min(round(height * image_height / 100), image_height - top))}
  end

  @doc """
  Downloads a stored variant by the URL pages link it at, straight from the
  bucket (not through our own `/img` route), never following redirects.
  """
  @spec fetch_stored(term()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch_stored(url) when is_binary(url) do
    case TcgCheap.Storage.object_path(url) do
      {:ok, path} -> download(TcgCheap.Storage.bucket_url(path), nil, [], false)
      :error -> {:error, :host_not_allowed}
    end
  end

  def fetch_stored(_url), do: {:error, :host_not_allowed}

  # `host` is the remote host the bot reads (nil: our own bucket, which is no
  # crawling and sends no bot identity).
  defp download(url, host, req_options, follow_redirects?) do
    case request(url, host, req_options, follow_redirects?) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> validate(body)
      {:ok, %Req.Response{status: 200, body: reason}} -> {:error, reason}
      {:ok, response} -> failed(response, host)
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(url, host, req_options, follow_redirects?) do
    deadline = System.monotonic_time(:millisecond) + @deadline_ms

    options = [
      url: url,
      decode_body: false,
      into: &bounded_body(&1, &2, deadline),
      connect_options: [timeout: 3_000],
      receive_timeout: 5_000,
      redirect: follow_redirects?,
      max_redirects: 3,
      retry: false
    ]

    task =
      Task.Supervisor.async_nolink(TcgCheap.Storage.DownloadSupervisor, fn ->
        if(host, do: Bot.new(options), else: Req.new(options))
        |> Req.merge(req_options)
        |> Req.Request.prepend_response_steps(
          image_redirect: &check_redirect(&1, host, req_options)
        )
        |> Req.request()
      end)

    case Task.yield(task, @deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, response}} -> {:ok, response}
      {:ok, {:error, exception}} -> {:error, {:transport, exception.__struct__}}
      _failed -> {:error, :download_timeout}
    end
  end

  # What a response that is not an image means. For a remote host the policy
  # decides: a redirect robots.txt forbids, a refusal (remembered: the host
  # is not asked for another image for a while) or a `Retry-After`.
  defp failed(response, nil), do: {:error, {:http_status, response.status}}

  defp failed(response, host) do
    case Req.Response.get_private(response, :bot_stop) do
      nil -> classified(Bot.classify(host, response), response, host)
      reason -> {:error, reason}
    end
  end

  defp classified({:stop, {:refused, status} = reason}, response, host) do
    host = String.downcase(host)
    if host_refused?(host, status, response), do: remember_refusal(host, status)
    {:error, reason}
  end

  defp classified({:stop, reason}, _response, _host), do: {:error, reason}
  defp classified(:ok, response, _host), do: {:error, {:http_status, response.status}}

  # A 403 from object storage that answers it for a missing image says nothing
  # about the host; a challenge or a 401 does.
  defp host_refused?(host, 403, response),
    do: host not in @missing_as_403 or Bot.challenge?(response)

  defp host_refused?(_host, _status, _response), do: true

  defp remember_refusal(host, status),
    do: Hosts.put_image_refusal(host, status, Hosts.now() + @refusal_ms)

  # Some shops generate a missing thumbnail behind a same-origin redirect.
  # Keep Req's redirect handling, but validate every hop before it can run: it
  # must stay on the host, and the host's robots.txt must allow its path.
  defp check_redirect({request, %{body: reason} = response}, _host, _req_options)
       when reason in [:too_large, :download_timeout],
       do: Req.Request.halt(request, response)

  defp check_redirect({request, %{status: status} = response}, host, req_options)
       when status in [301, 302, 303, 307, 308] and host != nil do
    with [location | _] <- Req.Response.get_header(response, "location"),
         {:ok, location} <- URI.new(location),
         target <- URI.merge(request.url, location),
         true <- ExternalImage.valid?(URI.to_string(target)),
         true <- origin(request.url) == origin(target),
         :ok <- Bot.permit(host, Bot.target(target), req_options, max_wait_ms: @redirect_wait_ms) do
      {request, response}
    else
      {:error, reason} ->
        Req.Request.halt(request, Req.Response.put_private(response, :bot_stop, reason))

      _blocked ->
        Req.Request.halt(request, response)
    end
  end

  defp check_redirect(request_response, _host, _req_options), do: request_response

  defp origin(uri),
    do: {uri.scheme, String.downcase(uri.host), uri.port || URI.default_port(uri.scheme)}

  defp bounded_body({:data, data}, {request, response}, deadline) do
    body = if is_binary(response.body), do: response.body, else: ""

    cond do
      byte_size(body) + byte_size(data) > @max_bytes ->
        {:halt, {request, %{response | body: :too_large}}}

      System.monotonic_time(:millisecond) > deadline ->
        {:halt, {request, %{response | body: :download_timeout}}}

      true ->
        {:cont, {request, %{response | body: body <> data}}}
    end
  end

  defp validate(body) do
    with type when is_binary(type) <- content_type(body),
         {:ok, image} <- Image.from_binary(body),
         true <- Image.width(image) * Image.height(image) <= @max_pixels do
      {:ok, body, type}
    else
      false -> {:error, :too_many_pixels}
      _invalid -> {:error, :invalid_image}
    end
  end

  defp content_type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"
  defp content_type(<<137, "PNG\r\n", 26, "\n", _rest::binary>>), do: "image/png"
  defp content_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: "image/webp"
  defp content_type(<<"GIF87a", _rest::binary>>), do: "image/gif"
  defp content_type(<<"GIF89a", _rest::binary>>), do: "image/gif"
  defp content_type(_body), do: nil
end
