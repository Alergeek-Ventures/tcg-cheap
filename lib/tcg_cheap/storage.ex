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

  @doc "The active storage service as `{module, opts}`, with this worktree's local S3 and server ports."
  @spec service() :: {module(), keyword()}
  def service,
    do:
      :tcg_cheap
      |> Application.fetch_env!(:storage)
      |> Config.service(%{
        "S3_PORT" => System.get_env("S3_PORT"),
        "PORT" => System.get_env("PORT")
      })

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
  The origins pages load public objects from, for the CSP image sources: where
  pages link them, and the bucket itself, which redirects cached before pages
  linked our own `/img` route (`TcgCheapWeb.RemoteImageController`) still reach.
  """
  @spec image_origins() :: [String.t()]
  def image_origins do
    {service, opts} = service()
    context = Context.new(opts)

    Enum.uniq([origin(service.public_base_url(context)), origin(service.bucket_url("", context))])
  end

  defp origin(url) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(url)
    to_string(%URI{scheme: scheme, host: host, port: port})
  end

  @doc """
  The object path of a URL pages link a public object at (`service().url/2`),
  else `:error`.
  """
  @spec object_path(String.t()) :: {:ok, String.t()} | :error
  def object_path(url) when is_binary(url) do
    base = public_base_url()

    if String.starts_with?(url, base) and url != base,
      do: {:ok, url |> String.replace_prefix(base, "") |> URI.decode()},
      else: :error
  end

  @doc "Where an object path is read from: the bucket itself, whatever pages link to."
  @spec bucket_url(String.t()) :: String.t()
  def bucket_url(path) do
    {service, opts} = service()
    service.bucket_url(path, Context.new(opts))
  end

  defp public_base_url do
    {service, opts} = service()
    service.public_base_url(Context.new(opts))
  end
end
