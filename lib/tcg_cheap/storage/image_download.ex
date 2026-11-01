defmodule TcgCheap.Storage.ImageDownload do
  @moduledoc "Bounded downloads of allowlisted raster images for background mirroring."

  alias TcgCheap.Catalogue.ExternalImage

  @max_bytes 15 * 1024 * 1024
  @max_pixels 40_000_000
  @deadline_ms 8_000

  @spec fetch(term(), keyword()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch(url, req_options \\ []) do
    if ExternalImage.valid?(url),
      do: download(url, req_options),
      else: {:error, :host_not_allowed}
  end

  @doc "Downloads a stored variant, never following redirects away from our storage."
  @spec fetch_stored(term()) :: {:ok, binary(), String.t()} | {:error, term()}
  def fetch_stored(url) when is_binary(url) do
    if String.starts_with?(url, TcgCheap.Storage.public_origin() <> "/"),
      do: download(url, []),
      else: {:error, :host_not_allowed}
  end

  def fetch_stored(_url), do: {:error, :host_not_allowed}

  defp download(url, req_options) do
    deadline = System.monotonic_time(:millisecond) + @deadline_ms

    task =
      Task.Supervisor.async_nolink(TcgCheap.Storage.DownloadSupervisor, fn ->
        req_options
        |> Req.new()
        |> Req.get(
          url: url,
          headers: [{"user-agent", "TcgCheap/1.0 (buying guide)"}],
          decode_body: false,
          into: &bounded_body(&1, &2, deadline),
          connect_options: [timeout: 3_000],
          receive_timeout: 5_000,
          redirect: false,
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
