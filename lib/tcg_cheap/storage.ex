defmodule TcgCheap.Storage do
  @moduledoc """
  Files we serve ourselves from object storage instead of hotlinking (AshStorage
  blobs). The services and buckets are configured in `config :tcg_cheap, :storage`:
  a public OVH bucket in production, the worktree's SeaweedFS in development.
  """

  use Ash.Domain, otp_app: :tcg_cheap

  alias AshStorage.Service.Context
  alias TcgCheap.Storage.Config

  resources do
    resource TcgCheap.Storage.Attachment do
      define :replace_image,
        action: :replace_image,
        args: [:record, :name, :body, :filename, :content_type]

      define :get_image_attachment,
        action: :for_owner,
        args: [:record_type, :record_id, :name],
        not_found_error?: false

      define :create_image_attachment, action: :create
      define :replace_attachment_blob, action: :replace_blob, args: [:blob_id]
    end

    resource TcgCheap.Storage.RemoteImage do
      define :register_remote_image, action: :register
      define :get_remote_image, action: :by_hash, args: [:hash]
      define :list_registered_remote_images, action: :registered, args: [:hashes]
      define :list_mirrored_remote_images, action: :mirrored, args: [:hashes]
      define :list_pending_remote_images, action: :pending, args: [:limit]
      define :record_remote_image_attempt, action: :record_attempt
      define :trim_remote_image_margins, action: :trim_margins
    end

    resource TcgCheap.Storage.Blob do
      define :create_blob, action: :create
      define :purge_blob, action: :purge_blob
    end
  end

  @doc "The active storage service as `{module, opts}`, with this worktree's local S3 port."
  @spec service() :: {module(), keyword()}
  def service,
    do:
      :tcg_cheap
      |> Application.fetch_env!(:storage)
      |> Config.service(%{"S3_PORT" => System.get_env("S3_PORT")})

  @doc "Public URLs of already mirrored variants, resolved in one database read."
  @spec mirrored_image_urls([String.t()], :thumbnail | :detail) :: %{String.t() => String.t()}
  def mirrored_image_urls(hashes, size) when size in [:thumbnail, :detail] do
    field = if size == :thumbnail, do: :thumbnail_key, else: :detail_key
    {service, opts} = service()
    context = Context.new(opts)

    for image <- list_mirrored_remote_images!(hashes, query: [select: [field]]),
        key = Map.fetch!(image, field),
        not is_nil(key),
        into: %{},
        do: {image.id, service.url(key, context)}
  end

  @doc """
  The origin public objects are served from, for the CSP image sources: the
  service's `public_base_url`, else its `endpoint_url`, both configured as a
  bare origin.
  """
  @spec public_origin() :: String.t()
  def public_origin do
    {_module, opts} = service()
    opts[:public_base_url] || opts[:endpoint_url]
  end
end
