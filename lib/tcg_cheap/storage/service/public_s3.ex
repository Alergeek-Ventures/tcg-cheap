defmodule TcgCheap.Storage.Service.PublicS3 do
  @moduledoc """
  S3-compatible storage service for objects that are publicly readable.

  This is the public-logo variant of `AshStorage.Service.S3`. Backend uploads
  add the signed `x-amz-acl: public-read` header, while reads use non-expiring
  public URLs and object management is delegated to the bundled S3 service.
  """

  @behaviour AshStorage.Service

  alias AshStorage.Service.Context
  alias AshStorage.Service.S3

  @impl true
  @spec service_opts_fields() :: keyword()
  def service_opts_fields do
    Keyword.put(S3.service_opts_fields(), :public_base_url, type: :string)
  end

  @impl true
  @spec upload(String.t(), iodata() | File.Stream.t(), Context.t()) ::
          :ok | {:error, term()}
  def upload(key, data, %Context{} = ctx) do
    full_key = prefixed_key(key, ctx)
    opts = ctx.service_opts
    bucket = Keyword.fetch!(opts, :bucket)

    put_opts =
      [
        url: "s3://#{bucket}/#{encode_key(full_key)}",
        body: data,
        headers: upload_headers(ctx, data)
      ]

    case Req.put(req(opts), put_opts) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @spec download(String.t(), Context.t()) :: {:ok, binary()} | {:error, term()}
  defdelegate download(key, ctx), to: S3

  @impl true
  @spec delete(String.t(), Context.t()) :: :ok | {:error, term()}
  defdelegate delete(key, ctx), to: S3

  @impl true
  @spec exists?(String.t(), Context.t()) :: {:ok, boolean()} | {:error, term()}
  defdelegate exists?(key, ctx), to: S3

  @impl true
  @spec head(String.t(), Context.t()) :: {:ok, map()} | {:error, term()}
  defdelegate head(key, ctx), to: S3

  @impl true
  @spec url(String.t(), Context.t()) :: String.t()
  def url(key, %Context{} = ctx) do
    case Keyword.get(ctx.service_opts, :public_base_url) do
      base_url when is_binary(base_url) ->
        base_url = String.trim(base_url)

        if base_url == "" do
          fallback_url(key, ctx)
        else
          String.trim_trailing(base_url, "/") <> "/" <> encode_key(prefixed_key(key, ctx))
        end

      nil ->
        fallback_url(key, ctx)

      base_url ->
        raise ArgumentError, "expected :public_base_url to be a string, got: #{inspect(base_url)}"
    end
  end

  defp req(opts) do
    signing_opts =
      Enum.reject(
        [
          region: Keyword.get(opts, :region, "us-east-1"),
          access_key_id: Keyword.get(opts, :access_key_id) || System.get_env("AWS_ACCESS_KEY_ID"),
          secret_access_key:
            Keyword.get(opts, :secret_access_key) || System.get_env("AWS_SECRET_ACCESS_KEY")
        ],
        fn {_key, value} -> is_nil(value) end
      )

    [aws_sigv4: [service: :s3] ++ signing_opts, retry: :transient]
    |> Req.new()
    |> ReqS3.attach(
      aws_endpoint_url_s3:
        Keyword.get(opts, :endpoint_url) ||
          "https://s3.#{Keyword.get(opts, :region, "us-east-1")}.amazonaws.com"
    )
    |> Req.merge(Keyword.get(opts, :req_options, []))
  end

  defp prefixed_key(key, %Context{service_opts: opts}) do
    (Keyword.get(opts, :prefix) || "") <> key
  end

  defp encode_key(key), do: URI.encode(key, &(&1 == ?/ or URI.char_unreserved?(&1)))

  defp fallback_url(key, %Context{} = ctx) do
    opts = Keyword.put(ctx.service_opts, :presigned, false)
    S3.url(key, %{ctx | service_opts: opts})
  end

  defp upload_headers(%Context{} = ctx, data) do
    checksum = if is_binary(data) or is_list(data), do: ctx.expected_md5

    Enum.reject(
      [
        {"x-amz-acl", "public-read"},
        {"content-type", ctx.content_type},
        {"content-md5", checksum}
      ],
      fn {_name, value} -> value in [nil, ""] end
    )
  end
end
