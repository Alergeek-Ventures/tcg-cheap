defmodule TcgCheap.Storage.ImageDownload do
  @moduledoc "Bounded downloads of allowlisted raster images for background mirroring, and their trimming."

  alias TcgCheap.Catalogue.ExternalImage

  @max_bytes 15 * 1024 * 1024
  @max_pixels 40_000_000
  @deadline_ms 8_000

  @spec fetch(term(), keyword()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch(url, req_options \\ []) do
    if ExternalImage.valid?(url),
      do: download(url, req_options, true),
      else: {:error, :host_not_allowed}
  end

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

  @doc "Downloads a stored variant, never following redirects away from our storage."
  @spec fetch_stored(term()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch_stored(url) when is_binary(url) do
    if String.starts_with?(url, TcgCheap.Storage.public_origin() <> "/"),
      do: download(url, [], false),
      else: {:error, :host_not_allowed}
  end

  def fetch_stored(_url), do: {:error, :host_not_allowed}

  defp download(url, req_options, follow_redirects?) do
    deadline = System.monotonic_time(:millisecond) + @deadline_ms

    task =
      Task.Supervisor.async_nolink(TcgCheap.Storage.DownloadSupervisor, fn ->
        req_options
        |> Req.new()
        |> Req.Request.prepend_response_steps(image_redirect: &check_redirect/1)
        |> Req.get(
          url: url,
          headers: [{"user-agent", "TcgCheap/1.0 (buying guide)"}],
          decode_body: false,
          into: &bounded_body(&1, &2, deadline),
          connect_options: [timeout: 3_000],
          receive_timeout: 5_000,
          redirect: follow_redirects?,
          max_redirects: 3,
          retry: false
        )
      end)

    case Task.yield(task, @deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Req.Response{status: 200, body: body}}} when is_binary(body) ->
        validate(body)

      {:ok, {:ok, %Req.Response{status: 200, body: reason}}} ->
        {:error, reason}

      {:ok, {:ok, %Req.Response{status: status}}} ->
        {:error, {:http_status, status}}

      {:ok, {:error, exception}} ->
        {:error, {:transport, exception.__struct__}}

      _failed ->
        {:error, :download_timeout}
    end
  end

  # Some shops generate a missing thumbnail behind a same-origin redirect.
  # Keep Req's redirect handling, but validate every hop before it can run.
  defp check_redirect({request, %{body: reason} = response})
       when reason in [:too_large, :download_timeout],
       do: Req.Request.halt(request, response)

  defp check_redirect({request, %{status: status} = response})
       when status in [301, 302, 303, 307, 308] do
    with [location | _] <- Req.Response.get_header(response, "location"),
         {:ok, location} <- URI.new(location),
         target <- URI.merge(request.url, location),
         true <- ExternalImage.valid?(URI.to_string(target)),
         true <- origin(request.url) == origin(target) do
      {request, response}
    else
      _blocked -> Req.Request.halt(request, response)
    end
  end

  defp check_redirect(request_response), do: request_response

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
