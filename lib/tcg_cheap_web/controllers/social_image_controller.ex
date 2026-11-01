defmodule TcgCheapWeb.SocialImageController do
  @moduledoc """
  Link-preview cards for the buying guide (see `TcgCheapWeb.SocialImage`).

  A card is rendered once per version of what it shows and kept in the
  public bucket (`social/…`); later requests are redirected there. The
  version is computed here from the current data, so the `v` parameter
  (which `TcgCheapWeb.SEO` puts in the URL for platforms that cache by URL)
  cannot force a new render. Crawlers send no session: cards are Polish.
  """

  use TcgCheapWeb, :controller

  alias AshStorage.Service.Context
  alias TcgCheap.Sealed.Guide
  alias TcgCheapWeb.SocialImage

  require Logger

  def home(conn, _params) do
    Gettext.put_locale(TcgCheapWeb.Gettext, "pl")
    serve(conn, "social/home-#{SocialImage.home_version()}.jpg", &SocialImage.home/0)
  end

  def product(conn, %{"slug" => slug}) do
    Gettext.put_locale(TcgCheapWeb.Gettext, "pl")

    case Guide.product(slug, DateTime.utc_now()) do
      {:ok, page} ->
        key = "social/products/#{page.product.slug}-#{SocialImage.product_version(page)}.jpg"
        serve(conn, key, fn -> SocialImage.product(page) end)

      :error ->
        conn |> put_resp_header("cache-control", "no-store") |> send_resp(404, "")
    end
  end

  defp serve(conn, key, render) do
    {service, opts} = TcgCheap.Storage.service()

    case service.exists?(key, Context.new(opts)) do
      {:ok, true} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> redirect(external: service.url(key, Context.new(opts)))

      _missing ->
        render_and_store(conn, service, opts, key, render)
    end
  end

  defp render_and_store(conn, service, opts, key, render) do
    case render.() do
      {:ok, jpeg} ->
        store(service, opts, key, jpeg)

        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> send_resp(200, jpeg)

      # Drawn without a photo that failed to download: served, not kept.
      {:partial, jpeg} ->
        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> put_resp_header("cache-control", "public, max-age=300")
        |> send_resp(200, jpeg)

      {:error, :busy} ->
        conn
        |> put_resp_header("retry-after", "5")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(503, "")

      {:error, reason} ->
        Logger.error("Link-preview card #{key} failed: #{inspect(reason)}")
        conn |> put_resp_header("cache-control", "no-store") |> send_resp(500, "")
    end
  end

  # The card is still served when storing it fails; the next request retries.
  defp store(service, opts, key, jpeg) do
    context =
      Context.new(opts,
        content_type: "image/jpeg",
        expected_md5: :md5 |> :crypto.hash(jpeg) |> Base.encode64()
      )

    with {:error, reason} <- service.upload(key, jpeg, context),
         do: Logger.warning("Link-preview card #{key} not stored: #{inspect(reason)}")
  end
end
