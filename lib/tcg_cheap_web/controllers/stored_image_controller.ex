defmodule TcgCheapWeb.StoredImageController do
  @moduledoc """
  Serves our object storage's images from our own origin (`/img/<key>`, the
  storage's `public_base_url`). They then share the page's HTTP/2 connection,
  where the bucket speaks only HTTP/1.1 and costs a phone a connection of its
  own: on a slow network that delayed the guide's largest image.

  Reads the bucket anonymously, so it serves only what is public anyway, and
  passes on raster images only, since they now come from our origin. Keys are
  never overwritten (`TcgCheap.Storage.Service.PublicS3`), so browsers may
  keep them for good.
  """
  use TcgCheapWeb, :controller

  require Logger

  alias TcgCheap.Storage

  @segment ~r/\A[A-Za-z0-9_-][A-Za-z0-9._-]*\z/
  @types ~w(image/webp image/jpeg image/png image/gif image/avif)

  def show(conn, %{"path" => segments}) do
    if Enum.all?(segments, &Regex.match?(@segment, &1)),
      do: relay(conn, Enum.join(segments, "/")),
      else: not_found(conn)
  end

  defp relay(conn, path) do
    case Req.get(Storage.bucket_url(path),
           decode_body: false,
           redirect: false,
           retry: false,
           connect_options: [timeout: 3_000],
           receive_timeout: 5_000
         ) do
      {:ok, %Req.Response{status: 200} = response} ->
        case Req.Response.get_header(response, "content-type") do
          [type | _] when type in @types -> send_image(conn, type, response.body)
          _other -> not_found(conn)
        end

      # OVH answers 403 for a key that does not exist.
      {:ok, %Req.Response{status: status}} when status in [403, 404] ->
        not_found(conn)

      failure ->
        Logger.warning("stored image #{path} unavailable: #{inspect(failure)}")

        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(502, "")
    end
  end

  # sobelow_skip ["XSS.SendResp"]
  # Raster image bytes from our own bucket, sent as the image type it stores with nosniff.
  # no-transform: Bandit would otherwise gzip the already compressed image.
  defp send_image(conn, type, body) do
    conn
    |> put_resp_content_type(type, nil)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable, no-transform")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, body)
  end

  defp not_found(conn) do
    conn
    |> put_resp_header("cache-control", "public, max-age=60")
    |> send_resp(404, "")
  end
end
