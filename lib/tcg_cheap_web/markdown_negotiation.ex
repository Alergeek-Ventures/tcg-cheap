defmodule TcgCheapWeb.MarkdownNegotiation do
  @moduledoc """
  Routes the markdown versions of the guide's pages to
  `TcgCheapWeb.MarkdownController` under `/md`: a page's path with `.md`
  (`/index.md` for the home page), or the page itself requested with
  `Accept: text/markdown` preferred over HTML. Browsers, link previews and
  `*/*` keep getting HTML.
  """

  import Plug.Conn

  def init(opts), do: opts

  # Plug.Head has already turned HEAD into GET.
  def call(%Plug.Conn{method: "GET", path_info: path_info} = conn, _opts) do
    with [_ | _] <- path_info,
         {:ok, page} <- strip_md(List.last(path_info)),
         page_path = List.replace_at(path_info, -1, page) |> home(),
         true <- guide_page?(page_path) do
      %{conn | path_info: ["md" | page_path]}
    else
      _not_md -> negotiate(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp negotiate(%Plug.Conn{path_info: path_info} = conn) do
    cond do
      not guide_page?(path_info) ->
        conn

      # A filtered or searched list has no markdown version.
      conn.query_string == "" and prefers_markdown?(get_req_header(conn, "accept")) ->
        conn |> put_resp_header("vary", "accept") |> Map.put(:path_info, ["md" | path_info])

      true ->
        put_resp_header(conn, "vary", "accept")
    end
  end

  defp strip_md(segment) do
    case String.split_at(segment, -3) do
      {page, ".md"} when page != "" -> {:ok, page}
      _other -> :error
    end
  end

  defp home(["index"]), do: []
  defp home(path_info), do: path_info

  defp guide_page?([]), do: true
  defp guide_page?(["ile-kosztuje-booster-pokemon"]), do: true
  defp guide_page?(["produkty", _slug]), do: true
  defp guide_page?(["rozszerzenia", _slug]), do: true
  defp guide_page?(["rozszerzenia", _slug, "karty", _card_slug]), do: true
  defp guide_page?(_path_info), do: false

  # Markdown only when the client names it and rates it at least as high as
  # HTML: agents that ask for markdown first, never a plain `*/*`.
  defp prefers_markdown?(accept) do
    qualities =
      accept
      |> Enum.flat_map(&String.split(&1, ","))
      |> Map.new(fn range ->
        [type | params] = range |> String.split(";") |> Enum.map(&String.trim/1)
        {String.downcase(type), quality(params)}
      end)

    markdown = Map.get(qualities, "text/markdown", 0.0)
    # HTML's quality comes from its most specific range.
    html = Enum.find_value(~w(text/html text/* */*), 0.0, &Map.get(qualities, &1))
    markdown > 0 and markdown >= html
  end

  defp quality(params) do
    Enum.find_value(params, 1.0, fn param ->
      case String.downcase(param) do
        "q=" <> value -> q_value(value)
        _other -> nil
      end
    end)
  end

  # An unreadable quality rules the range out.
  defp q_value(value) do
    case Float.parse(value) do
      {q, _rest} -> q
      :error -> 0.0
    end
  end
end
