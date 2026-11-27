defmodule TcgCheapWeb.LegacyPaths do
  @moduledoc """
  Permanent redirects, in one hop, from the guide's URL forms without a region
  prefix, which search engines still hold, to the Polish region's URL:
  `/produkty/<slug>` to `/pl/produkty/<slug>`, a set or card under a name it
  no longer has straight to its current one, the markdown versions to theirs
  and the link-preview cards (`/og/…`) to `/og/pl/…`. The query is kept, but
  for the parameters a set page absorbs (`TcgCheapWeb.SetCanonical`); a
  trailing slash is dropped.

  It runs before `TcgCheapWeb.MarkdownNegotiation`, which knows only the
  regions' paths. The root `/` is Poland's home page, where
  `TcgCheapWeb.SetCanonical` moves the list's filter parameters.
  """

  import Plug.Conn

  alias Plug.Conn.Query
  alias TcgCheap.Cards
  alias TcgCheapWeb.{PageMarkdown, Paths, Region, SetCanonical}

  def init(opts), do: opts

  # Plug.Head has already turned HEAD into GET.
  def call(%Plug.Conn{method: "GET", path_info: path_info} = conn, _opts) do
    if legacy?(path_info) do
      conn = fetch_query_params(conn)
      {path, query} = target(path_info, conn)
      location = if query == "", do: path, else: path <> "?" <> query

      conn |> put_resp_header("location", location) |> send_resp(301, "") |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp legacy?(["og"]), do: true
  defp legacy?(["og" | rest]), do: not region?(rest) and legacy?(rest)
  defp legacy?([first | _rest]), do: String.replace_suffix(first, ".md", "") in polish_segments()
  defp legacy?([]), do: false

  defp region?([code | _rest]), do: Region.fetch(code) != :error
  defp region?([]), do: false

  # The first segments of Poland's pages: the guide's paths before regions.
  defp polish_segments do
    %Region{slugs: slugs, pages: pages} = Region.poland()
    Map.values(slugs) ++ Map.values(pages)
  end

  # Link-preview cards keep their path: a renamed set's card was gone before.
  defp target(["og" | rest], conn), do: {"/og/pl" <> encode(rest), conn.query_string}

  defp target(path_info, conn) do
    {segments, markdown?} = strip_markdown(path_info)

    {path, query} =
      case Paths.parse(Enum.join(["/pl" | segments], "/")) do
        {:ok, _region, page} -> current(page, conn)
        :error -> {"/pl" <> encode(segments), conn.query_string}
      end

    if markdown?, do: {PageMarkdown.url_for(path), query}, else: {path, query}
  end

  defp strip_markdown(path_info) do
    case String.split_at(List.last(path_info), -3) do
      {page, ".md"} when page != "" -> {List.replace_at(path_info, -1, page), true}
      _html -> {path_info, false}
    end
  end

  # A set and a card under their current names.
  defp current({:expansion, slug} = page, conn) do
    with true <- flat?(conn.query_params),
         {:ok, path, params} <- SetCanonical.resolve(%{"slug" => slug}, conn.query_params) do
      {path, URI.encode_query(params)}
    else
      _unknown -> {Paths.page_path(Region.poland(), page), conn.query_string}
    end
  end

  defp current({:card, set, card} = page, conn) do
    case Cards.Guide.find(set, card) do
      {:ok, _card, _name, path} -> {Paths.localize(Region.poland(), path), conn.query_string}
      :error -> {Paths.page_path(Region.poland(), page), conn.query_string}
    end
  end

  defp current(page, conn), do: {Paths.page_path(Region.poland(), page), conn.query_string}

  @doc """
  The Polish URL for an old home page entry point with these query params:
  the card list or a set page for the filters that belong there, else the
  Polish home page; `{path, query}`.
  """
  @spec home(%{String.t() => term()}) :: {String.t(), String.t()}
  def home(params) do
    with true <- flat?(params),
         {:ok, path, params} <- SetCanonical.resolve(%{}, params) do
      {path, URI.encode_query(params)}
    else
      _home -> {Paths.page_path(Region.poland(), :home), Query.encode(params)}
    end
  end

  # Nested params cannot be carried over by SetCanonical.
  defp flat?(params), do: Enum.all?(params, fn {_key, value} -> is_binary(value) end)

  defp encode([]), do: ""

  defp encode(segments),
    do:
      "/" <>
        Enum.map_join(segments, "/", fn segment ->
          URI.encode(segment, &URI.char_unreserved?/1)
        end)
end
