import Config

# Digested static files, listed in the manifest `mix assets.deploy` generates.
config :tcg_cheap, TcgCheapWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

# Force SSL (this also sends the HSTS header); compile-time setting. Behind
# the proxy the scheme comes from X-Forwarded-Proto.
config :tcg_cheap, TcgCheapWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      hosts: ["localhost", "127.0.0.1"]
    ]
  ]

# OVH Object Storage in Warsaw. The bucket is private (no anonymous listing
# or writes); every object is uploaded public-read, so pages link to it
# without presigned URLs. Keys come from AWS_ACCESS_KEY_ID and
# AWS_SECRET_ACCESS_KEY (Infisical prod /app). Pages link objects through our
# own /img route (TcgCheapWeb.StoredImageController): the bucket speaks only
# HTTP/1.1 and would cost a phone a connection of its own.
config :tcg_cheap, :storage,
  services: [
    s3_public: [
      opts: [
        bucket: "tcg-cheap-public",
        region: "waw",
        endpoint_url: "https://s3.waw.io.cloud.ovh.net",
        public_base_url: "https://tcg.cheap/img",
        bucket_url: "https://tcg-cheap-public.s3.waw.io.cloud.ovh.net"
      ]
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Log lines from :info up also go to Sentry Logs.
config :sentry, logs: [level: :info]
