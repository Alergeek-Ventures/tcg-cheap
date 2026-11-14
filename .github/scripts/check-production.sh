#!/usr/bin/env bash
# Checks that production runs the given revision and serves every kind of
# public page in every region the sitemap lists: the region's home and
# one-segment pages (lists, articles), the first page of each kind with a
# slug (products and expansions), the first single card, the Markdown
# versions of the home and the first such page, and link-preview images, plus
# the bot page, robots.txt and llms.txt. Coolify's own health check only
# covers /health, which renders no page.
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

# The regions and their pages come from the sitemap: without entries there
# is nothing to request, which says nothing about the release.
if ! grep -q "<loc>$base/[^<]*</loc>" <<<"$sitemap"; then
  echo "::error::$base/sitemap.xml lists no page"
  exit 2
fi

# Prints "<kind> <path>" for the pages to check, derived from the sitemap so
# that a new region, or a region's own path words, need no change here. A
# region is the first path segment of a <loc>; its pages are
#   /<rr>/                                  home
#   /<rr>/<word>                            lists and articles
#   /<rr>/<word>/<slug>                     products and expansions
#   /<rr>/<word>/<slug>/<word>/<card-slug>  single cards
# Kinds: page (HTML), md (Markdown version), og (link preview), warn.
#
# Per region this is the home, every one-segment page, the first page of each
# two-segment kind, the first card, two Markdown pages and the home's and
# product's link previews, so the number of requests grows with the number
# of regions and with the number of kinds, never with the size of the
# catalogue.
#
# Only the product kind has a link preview in every region: expansions and
# cards have one in Poland alone. The expansion kind is the first word of the
# card paths, so the other two-segment kind is the product one.
select_urls() {
  { grep -o '<loc>[^<]*</loc>' <<<"$sitemap" || true; } |
    sed -E 's|<loc>[a-z]+://[^/]*(/[^<]*)</loc>|\1|' | awk '
    {
      n = split(substr($0, 2), s, "/")
      if (s[n] == "") n--
      r = s[1]
      if (!(r in seen)) { seen[r] = 1; regions[++count] = r }
      if (n == 1 && !(r in home)) home[r] = $0
      else if (n == 2) ones[r] = ones[r] " " $0
      else if (n == 3 && !((r, s[2]) in kind)) {
        kind[r, s[2]] = 1
        twos[r] = twos[r] " " $0
        words[r] = words[r] " " s[2]
        if (!(r in firsttwo)) firsttwo[r] = $0
      }
      else if (n == 5 && !(r in card)) { card[r] = $0; cardword[r] = s[2] }
    }
    END {
      for (i = 1; i <= count; i++) {
        r = regions[i]
        if (r in home) { print "page " home[r]; print "md /" r "/index.md" }
        else print "warn The sitemap lists no home page in " r
        m = split(ones[r], list, " ")
        for (j = 1; j <= m; j++) print "page " list[j]
        if (r in firsttwo) print "md " firsttwo[r] ".md"
        else print "warn The sitemap lists no product or expansion page in " r
        m = split(twos[r], list, " ")
        split(words[r], word, " ")
        for (j = 1; j <= m; j++) {
          print "page " list[j]
          if ((r in card) && word[j] != cardword[r]) print "og /og" list[j]
        }
        if (r in card) print "page " card[r]
        else print "warn The sitemap lists no card page in " r
        print "og /og/" r "/"
      }
    }'
}

# The root only redirects to a region (TcgCheapWeb.RegionController), so the
# pages checked are the regions' own. /pl/bot is the one page named here: the
# sitemap does not list it.
urls=(
  "$base/pl/bot"
  "$base/robots.txt"
  "$base/llms.txt"
)

# Link previews may answer with a redirect to a stored image.
previews=()

while read -r kind path; do
  case "$kind" in
    page | md) urls+=("$base$path") ;;
    og) previews+=("$base$path") ;;
    warn) echo "::warning::$path" ;;
  esac
done < <(select_urls)

result=0

# check <url> <accepted statuses, as a regular expression>
check() {
  local url="$1" accepted="$2" attempt status

  # A slow first render after a restart is not a broken page. Pages answer
  # 200 directly; a redirect where only 200 is accepted is a change worth
  # looking at.
  for attempt in 1 2 3; do
    status="$(curl -sS -o /dev/null --max-time 30 -w '%{http_code}' "$url" || true)"
    [[ "$status" =~ ^($accepted)$ ]] && break
    [ "$attempt" -lt 3 ] && sleep 10
  done

  echo "$status $url"

  if [[ "$status" =~ ^($accepted)$ ]]; then
    return
  fi

  case "$status" in
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
}

for url in "${urls[@]}"; do
  check "$url" 200
done

for url in "${previews[@]}"; do
  check "$url" '200|302'
done

exit "$result"
