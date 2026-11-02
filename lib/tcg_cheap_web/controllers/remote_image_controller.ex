defmodule TcgCheapWeb.RemoteImageController do
  @moduledoc "Serves only previously mirrored remote images; never fetches remote sources."
  use TcgCheapWeb, :controller

  alias AshStorage.Service.Context
  alias TcgCheap.Storage

  @placeholder ~s(<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1" viewBox="0 0 1 1"></svg>)

  def show(conn, %{"hash" => hash, "size" => size} = params)
      when size in ["thumbnail", "detail"] do
    with true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, hash),
         {:ok, image} when not is_nil(image) <- Storage.get_remote_image(hash),
         key when is_binary(key) <- stored_key(image, size) do
      {service, opts} = Storage.service()
      url = service.url(key, Context.new(opts))

      conn
      |> put_resp_header("cache-control", cache_control(image, params["v"]))
      |> redirect(external: url)
    else
      _ -> placeholder(conn)
    end
  end

  def show(conn, _params), do: placeholder(conn)

  # Files that will be replaced (an image waiting to be mirrored again, or a
  # logo asked for trimmed but not trimmed yet) are deleted then: a redirect
  # to them is cached briefly.
  defp cache_control(%{attempted_at: nil}, _version), do: "public, max-age=60"
  defp cache_control(%{trim_margins: false}, "trimmed"), do: "public, max-age=60"
  defp cache_control(_image, _version), do: "public, max-age=86400"

  defp stored_key(image, "thumbnail"), do: image.thumbnail_key
  defp stored_key(image, "detail"), do: image.detail_key

  defp placeholder(conn) do
    conn
    |> put_resp_header("cache-control", "public, max-age=60")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_content_type("image/svg+xml")
    |> send_resp(200, @placeholder)
  end
end
