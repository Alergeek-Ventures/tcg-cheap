# Deployment and operations

## Build and run

Build the non-root release image with either engine:

```sh
podman build --format docker -f deployment/Containerfile.app -t tcg-cheap:release .
# or: docker build -f deployment/Containerfile.app -t tcg-cheap:release .
```

Production requires `DATABASE_URL` and `SECRET_KEY_BASE`. Set `PHX_HOST` to the
public HTTPS host. `PORT` defaults to `4004`; `POOL_SIZE`, `ECTO_IPV6`, and
`DNS_CLUSTER_QUERY` are optional. `ADMIN_AUTH_SIGNING_SECRET` is optional and
falls back to `SECRET_KEY_BASE`, but should be a separate secret when possible.
Never put values in the image or shell history; inject them through the runtime
secret mechanism.

Run migrations before starting a new image:

```sh
podman run --rm --env-file production.env tcg-cheap:release /app/bin/tcg_cheap eval "TcgCheap.Release.migrate()"
```

The same command works with `docker run`. Start and verify the service:

```sh
podman run -d --name tcg-cheap --env-file production.env -p 4004:4004 tcg-cheap:release
curl --fail http://127.0.0.1:4004/health/live
curl --fail http://127.0.0.1:4004/health
podman healthcheck run tcg-cheap
```

`/health/live` confirms that the web process can answer and is used by the
container health check. `/health` is the fail-closed readiness check for
PostgreSQL, Oban queues, and acquisition-budget configuration. Keep both paths
behind infrastructure monitoring; neither calls an external provider.

## First administrator

For a one-shot operation, inject `ADMIN_EMAIL` and `ADMIN_PASSWORD` only into
the migration/provisioning command:

```sh
podman run --rm --env-file production.env -e ADMIN_EMAIL -e ADMIN_PASSWORD \
  tcg-cheap:release /app/bin/tcg_cheap eval "TcgCheap.Release.provision_admin()"
```

Remove `ADMIN_EMAIL` and `ADMIN_PASSWORD` immediately afterwards. Keep an
independently configured `ADMIN_AUTH_SIGNING_SECRET`. The release never prints
the password or validation detail; missing variables fail with the name only.

## Backups, rollback, and incidents

Back up PostgreSQL using the platform's encrypted, tested snapshot/PITR process
and periodically verify a restore into an isolated database. Restore only after
stopping writers and checking the target/version; do not restore over production
without an explicit change record.

Deploy by building a new immutable image, migrating forward, then replacing the
old process. Roll back the image only when its schema is compatible. Never
blindly reverse data migrations: restore a tested database backup or ship a
forward-compatible corrective migration instead.

Oban jobs are persisted in PostgreSQL. Observe queue depth, failures, retries,
and scheduled jobs; pause or drain queues during maintenance and resume after
the application is healthy. Provider controls and circuit breakers should be
used as kill switches for failing or rate-limited upstreams. They prevent fresh
acquisition work while cached, stale data remains available; they are not a
substitute for fixing credentials, limits, or provider outages.

Sealed adapters are disabled by default and must not be treated as a claim that
production data exists. During an incident, keep serving the last known cached
or explicitly stale data, label its age, and disable refreshes until the source
and persistence paths are safe.
