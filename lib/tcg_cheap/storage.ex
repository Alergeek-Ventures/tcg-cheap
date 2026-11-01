defmodule TcgCheap.Storage do
  @moduledoc """
  Files we serve ourselves from object storage instead of hotlinking (AshStorage
  blobs). The services and buckets are configured in `config :tcg_cheap, :storage`:
  a public OVH bucket in production, the worktree's SeaweedFS in development.
  """

  use Ash.Domain, otp_app: :tcg_cheap

  alias TcgCheap.Storage.Config

  resources do
    resource TcgCheap.Storage.Attachment
    resource TcgCheap.Storage.Blob
  end

  @doc "The active storage service as `{module, opts}`, with this worktree's local S3 port."
  @spec service() :: {module(), keyword()}
  def service,
    do:
      :tcg_cheap
      |> Application.fetch_env!(:storage)
      |> Config.service(%{"S3_PORT" => System.get_env("S3_PORT")})

  @doc "The origin public objects are served from, for the CSP image sources."
  @spec public_origin() :: String.t()
  def public_origin do
    {_module, opts} = service()
    %URI{} = uri = URI.parse(opts[:public_base_url] || opts[:endpoint_url])

    URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port})
  end
end
