defmodule TcgCheapWeb.Locale do
  @moduledoc "Session locale for public guide requests and their LiveView processes."
  import Plug.Conn, only: [get_session: 2]
  import Phoenix.Component, only: [assign: 3]

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = normalize(get_session(conn, :locale))
    Gettext.put_locale(TcgCheapWeb.Gettext, locale)
    conn |> Plug.Conn.assign(:locale, locale) |> Plug.Conn.assign(:html_lang, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["locale"])
    Gettext.put_locale(TcgCheapWeb.Gettext, locale)

    {:cont,
     socket
     |> assign(:locale, locale)
     |> assign(:html_lang, locale)
     |> Phoenix.LiveView.attach_hook(:locale_path, :handle_params, fn _params, uri, socket ->
       uri = URI.parse(uri)
       path = uri.path <> if(uri.query, do: "?" <> uri.query, else: "")
       {:cont, assign(socket, :locale_return_to, path)}
     end)}
  end

  def normalize(locale) when locale in ["pl", "en"], do: locale
  def normalize(_locale), do: "pl"

  # Only absolute local paths, never authority URLs, backslashes or control characters.
  def local_path("/" <> _rest = path) do
    decoded = URI.decode(path)

    if String.valid?(decoded) and String.starts_with?(decoded, "/") and
         not String.starts_with?(decoded, "//") and not String.contains?(decoded, "\\") and
         not Regex.match?(~r/[\x00-\x1f\x7f]/, decoded),
       do: path,
       else: "/"
  end

  def local_path(_path), do: "/"
end
