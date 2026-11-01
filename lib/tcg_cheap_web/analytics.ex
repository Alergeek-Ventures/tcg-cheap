defmodule TcgCheapWeb.Analytics do
  @moduledoc false

  def config(%Plug.Conn{path_info: ["admin" | _]}), do: nil

  def config(_conn) do
    settings = Application.get_env(:tcg_cheap, :posthog, [])

    case Keyword.get(settings, :api_key) do
      key when is_binary(key) and key != "" ->
        host = Keyword.fetch!(settings, :api_host)

        %{
          api_key: key,
          api_host: host,
          asset_host: String.replace(host, ".i.posthog.com", "-assets.i.posthog.com")
        }

      _key ->
        nil
    end
  end
end
