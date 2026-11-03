defmodule TcgCheapWeb.SingleCanonical do
  @moduledoc "Permanent redirects for renamed cards and expansions before LiveView renders."
  import Plug.Conn
  alias TcgCheap.Sealed.CardGuide
  def init(opts), do: opts

  def call(conn, _opts) do
    case CardGuide.find(conn.path_params["slug"], conn.path_params["card_slug"]) do
      {:ok, _card, _name, path} when path != conn.request_path ->
        conn |> put_resp_header("location", path) |> send_resp(301, "") |> halt()

      {:ok, _card, _name, _path} ->
        conn

      :error ->
        raise TcgCheapWeb.SingleLive.NotFound
    end
  end
end
