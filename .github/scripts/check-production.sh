#!/usr/bin/env bash
# Checks that production runs the given revision and serves its pages: the
# regions' home pages, the booster price guide, the Markdown home, and the
# first Polish product, expansion and single card the sitemap lists. Coolify's own health
# check only covers /health, which renders no page.
#
#   check-production.sh <revision> [base URL]
#
# Exits 1 when a page answers an error (the release is broken), and 2 when
# the check cannot tell: production runs another revision, or production or
# the sitemap does not answer at all.
set -euo pipefail

revision="$1"
base="${2:-https://tcg.cheap}"

# Coolify reports the deployment finished once the new container is healthy,
# but the proxy may still route to the old one for a moment.
deadline=$((SECONDS + 180))
until running="$(curl -fsS --max-time 10 "$base/health/live" | jq -r .revision)" &&
  [ "$running" = "$revision" ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "::error::Production runs ${running:-nothing reachable}, not $revision"
    exit 2
  fi

  sleep 5
done

echo "Production runs $revision"

if ! sitemap="$(curl -fsS --retry 3 --retry-all-errors --max-time 30 "$base/sitemap.xml")"; then
  echo "::error::$base/sitemap.xml did not answer"
  exit 2
fi

first_loc() { grep -o "<loc>$base/$1</loc>" <<<"$sitemap" | sed -n '1s/<[^>]*>//gp' || true; }

# The root only redirects to a region (TcgCheapWeb.RegionController), so the
# pages checked are the regions' own.
urls=(
  "$base/pl/"
  "$base/hu/"
  "$base/pl/ile-kosztuje-booster-pokemon"
  "$base/pl/index.md"
  "$(first_loc 'pl/produkty/[^<]*')"
  "$(first_loc 'pl/rozszerzenia/[^/<]*')"
  "$(first_loc 'pl/rozszerzenia/[^/<]*/karty/[^<]*')"
)

result=0

for url in "${urls[@]}"; do
  if [ -z "$url" ]; then
    echo "::warning::The sitemap lists no product, expansion or card page"
    continue
  fi

  # A slow first render after a restart is not a broken page. Every page
  # answers 200 directly; a redirect here is a change worth looking at.
  for attempt in 1 2 3; do
    status="$(curl -sS -o /dev/null --max-time 30 -w '%{http_code}' "$url" || true)"
    [ "$status" = 200 ] && break
    [ "$attempt" -lt 3 ] && sleep 10
  done

  echo "$status $url"

  case "$status" in
    200) ;;
    # No answer, or Cloudflare not reaching the origin: not the page's fault.
    000 | 52?)
      echo "::error::$url did not answer ($status)"
      [ "$result" = 1 ] || result=2
      ;;
    *)
      echo "::error::$url answered $status"
      result=1
      ;;
  esac
done

exit "$result"
