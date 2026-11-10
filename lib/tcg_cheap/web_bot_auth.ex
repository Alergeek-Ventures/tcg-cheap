defmodule TcgCheap.WebBotAuth do
  @moduledoc """
  Identifies the shop reader with Web Bot Auth: requests carry HTTP Message
  Signatures (RFC 9421) made with our Ed25519 `key`, and the public key is
  published at `/.well-known/http-message-signatures-directory` on `agent`,
  our own site (`TcgCheapWeb.CrawlController`).

  Shopify gives bots that do not sign their requests its strictest rate
  limits, and signed requests from a bot registered with Shopify higher ones
  (shopify.dev changelog, "Bots and agents should identify themselves via Web
  Bot Auth", May 2026). In November 2026 our unsigned listing requests got 429
  `local_rate_limited` (`Retry-After: 60`), still after waiting it out.

  A request signs its `@authority` and its `Signature-Agent` for one minute;
  the directory signs the `@authority` it was requested from. Both follow
  draft-meunier-web-bot-auth-architecture and
  draft-meunier-http-message-signatures-directory as Cloudflare documents
  them. Without a key, requests go out unsigned and no directory is served.
  """

  require Logger

  @request_tag "web-bot-auth"
  @directory_tag "http-message-signatures-directory"
  @lifetime_s 60

  @doc """
  A Req request step that signs the request when a key is configured, and
  warns that it goes out unsigned otherwise.
  """
  @spec sign(Req.Request.t()) :: Req.Request.t()
  def sign(%Req.Request{} = request) do
    case config() do
      %{key: nil} ->
        Logger.warning("unsigned request to #{request.url.host}: WEB_BOT_AUTH_KEY is not set")
        request

      %{key: key, agent: agent} ->
        # Signature-Agent is a structured field string, hence the quotes.
        agent = ~s("#{agent}")

        {input, signature} =
          signature(
            key,
            [{~s("@authority"), authority(request.url)}, {~s("signature-agent"), agent}],
            @request_tag
          )

        request
        |> Req.Request.put_header("signature-agent", agent)
        |> Req.Request.put_header("signature-input", input)
        |> Req.Request.put_header("signature", signature)
    end
  end

  @doc """
  The key directory asked for at `url`: a JSON Web Key Set with our public
  key and the `Signature-Input` and `Signature` response headers that sign
  it, or `:error` without a key.
  """
  @spec directory(URI.t()) :: {:ok, String.t(), [{String.t(), String.t()}]} | :error
  def directory(%URI{} = url) do
    case config() do
      %{key: nil} ->
        :error

      %{key: key} ->
        {input, signature} =
          signature(key, [{~s("@authority";req), authority(url)}], @directory_tag)

        {:ok, Jason.encode!(%{keys: [jwk(key)]}),
         [{"signature-input", input}, {"signature", signature}]}
    end
  end

  defp config do
    config = Application.fetch_env!(:tcg_cheap, __MODULE__)
    %{key: Keyword.fetch!(config, :key), agent: Keyword.fetch!(config, :agent)}
  end

  # The Signature-Input and Signature values (label sig1) over `components`,
  # each `{serialized identifier, value}` (RFC 9421, section 2.5).
  defp signature(key, components, tag) do
    created = System.system_time(:second)
    nonce = 32 |> :crypto.strong_rand_bytes() |> Base.encode64()

    params =
      "(#{Enum.map_join(components, " ", &elem(&1, 0))})" <>
        ~s(;created=#{created};expires=#{created + @lifetime_s};keyid="#{key_id(key)}") <>
        ~s(;alg="ed25519";nonce="#{nonce}";tag="#{tag}")

    base =
      Enum.map_join(components, "", fn {identifier, value} -> "#{identifier}: #{value}\n" end) <>
        ~s("@signature-params": #{params})

    signature = :crypto.sign(:eddsa, :none, base, [key, :ed25519])
    {"sig1=#{params}", "sig1=:#{Base.encode64(signature)}:"}
  end

  # The target host, with the port only when it is not the scheme's default.
  defp authority(%URI{scheme: scheme, host: host, port: port}) do
    host = String.downcase(host)
    if port == URI.default_port(scheme), do: host, else: "#{host}:#{port}"
  end

  defp jwk(key) do
    {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519, key)
    %{kty: "OKP", crv: "Ed25519", x: Base.url_encode64(public_key, padding: false)}
  end

  # The JWK thumbprint (RFC 7638): the SHA-256 of the required members in
  # lexicographic order, without whitespace.
  defp key_id(key) do
    %{crv: crv, kty: kty, x: x} = jwk(key)

    :sha256
    |> :crypto.hash(~s({"crv":"#{crv}","kty":"#{kty}","x":"#{x}"}))
    |> Base.url_encode64(padding: false)
  end
end
