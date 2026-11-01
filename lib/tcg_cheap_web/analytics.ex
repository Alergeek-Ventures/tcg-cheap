defmodule TcgCheapWeb.Analytics do
  @moduledoc false

  # Shared with the browser so SDK requests and the proxy use the same routes.
  @proxy_paths %{
    "/i/v0/e/" => "/_x/19a4/",
    "/e/" => "/_x/27bf/",
    "/s/" => "/_x/3d81/",
    "/flags/" => "/_x/4c6e/",
    "/array/" => "/_x/5ab2/",
    "/static/" => "/_x/6f93/"
  }

  def proxy_paths, do: @proxy_paths

  def config(%Plug.Conn{path_info: ["admin" | _]}), do: nil

  def config(_conn) do
    settings = Application.get_env(:tcg_cheap, :posthog, [])

    case Keyword.get(settings, :api_key) do
      key when is_binary(key) and key != "" ->
        %{api_key: key, proxy_paths: @proxy_paths}

      _key ->
        nil
    end
  end
end
