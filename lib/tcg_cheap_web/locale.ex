defmodule TcgCheapWeb.Locale do
  @moduledoc """
  The region and language of public guide requests and their LiveView
  processes.

  The region comes from the route (`plug TcgCheapWeb.Locale, "pl"`, or
  `{"pl", :default_language}` for the cookieless markdown and link-preview
  cards, and
  `on_mount: {TcgCheapWeb.Locale, "pl"}` in the region's live session). The
  language is the visitor's choice, kept by their browser in localStorage
  and mirrored in the `lang` cookie so the first response already renders
  it; without one, the region's own. The live session's `session/1` hands
  the request's language and region hint to the LiveView, which cannot read
  cookies.

  A region hint (`region_hint`) suggests the region of the visitor's country
  (Cloudflare's `cf-ipcountry`) when it is another region's and the visitor
  has not chosen one yet (the `region` cookie); nothing redirects by it.
  """

  import Plug.Conn, except: [assign: 3]
  import Phoenix.Component, only: [assign: 3]

  alias TcgCheapWeb.Region

  @language_cookie "lang"
  @region_cookie "region"
  @year 365 * 24 * 60 * 60
  @control_character ~r/[\x00-\x1f\x7f]/

  def language_cookie, do: @language_cookie
  def region_cookie, do: @region_cookie

  def init(opts), do: opts

  # Markdown and link-preview cards: no session or cookies, the region's language.
  def call(conn, {region_code, :default_language}) do
    region = Region.fetch!(region_code)
    put(region, region.language)

    conn
    |> Plug.Conn.assign(:region, region)
    |> Plug.Conn.assign(:locale, region.language)
  end

  def call(conn, region_code) do
    region = Region.fetch!(region_code)
    conn = fetch_cookies(conn)
    {language, conn} = language(conn, region)
    put(region, language)

    conn
    |> Plug.Conn.assign(:region, region)
    |> Plug.Conn.assign(:locale, language)
    |> Plug.Conn.assign(:html_lang, language)
    |> Plug.Conn.assign(:region_hint, region_hint(conn, region))
  end

  # The language chosen before it moved to a cookie lived in the session:
  # carried over once.
  defp language(conn, region) do
    case {Region.language(conn.cookies[@language_cookie]), get_session(conn, :locale)} do
      {nil, legacy} when legacy in ["pl", "en"] ->
        {legacy, conn |> delete_session(:locale) |> put_language_cookie(legacy)}

      {nil, _legacy} ->
        {region.language, conn}

      {language, _legacy} ->
        {language, conn}
    end
  end

  defp region_hint(conn, region) do
    with nil <- conn.cookies[@region_cookie],
         [country] <- get_req_header(conn, "cf-ipcountry"),
         %Region{code: code} = suggested when code != region.code <-
           Enum.find(Region.all(), &(&1.market.country == country)) do
      suggested.code
    else
      _no_hint -> nil
    end
  end

  @doc "What the live session's LiveViews need from the request (see the moduledoc)."
  def session(conn),
    do: %{"locale" => conn.assigns.locale, "region_hint" => conn.assigns.region_hint}

  def on_mount(region_code, _params, session, socket) do
    region = Region.fetch!(region_code)
    language = Region.language(session["locale"]) || region.language
    put(region, language)

    {:cont,
     socket
     |> assign(:region, region)
     |> assign(:locale, language)
     |> assign(:html_lang, language)
     |> assign(:region_hint, session["region_hint"])
     |> Phoenix.LiveView.attach_hook(:current_path, :handle_params, fn _params, uri, socket ->
       uri = URI.parse(uri)
       # As the browser's location writes it: an empty query ("/x?") is none.
       path = uri.path <> if(uri.query in [nil, ""], do: "", else: "?" <> uri.query)
       {:cont, assign(socket, :current_path, path)}
     end)}
  end

  @doc "Renders this process in the region and language."
  @spec put(Region.t(), String.t()) :: :ok
  def put(region, language) do
    Region.put(region)
    Gettext.put_locale(TcgCheapWeb.Gettext, language)
    :ok
  end

  @doc "Remembers a language for the next requests, as the browser's control does."
  @spec put_language_cookie(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put_language_cookie(conn, language),
    do: put_resp_cookie(conn, @language_cookie, language, cookie_options())

  @doc "Remembers the region the visitor chose, for the root's redirect and the region hint."
  @spec put_region_cookie(Plug.Conn.t(), Region.t()) :: Plug.Conn.t()
  def put_region_cookie(conn, region),
    do: put_resp_cookie(conn, @region_cookie, region.code, cookie_options())

  # The browser's language control writes the language cookie too.
  defp cookie_options, do: [max_age: @year, http_only: false, same_site: "Lax"]

  # Only absolute local paths, never authority URLs, backslashes or control characters.
  def local_path("/" <> _rest = path) do
    decoded = URI.decode(path)

    if String.valid?(decoded) and String.starts_with?(decoded, "/") and
         not String.starts_with?(decoded, "//") and not String.contains?(decoded, "\\") and
         not Regex.match?(@control_character, decoded),
       do: path,
       else: "/"
  end

  def local_path(_path), do: "/"
end
