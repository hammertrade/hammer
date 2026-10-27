#!/usr/bin/env bash
# Builds the site and publishes the static files to Cloudflare, where hammertrade.xyz points.
#
#   tools/deploy-site.sh                                         live Ethereum exchange (.env.production)
#   VITE_PREVIEW=1 tools/deploy-site.sh                          practice preview, no real funds
#
# The files are built here and uploaded as they are; nothing runs on the server. The site answers on
# hammertrade.xyz, www.hammertrade.xyz and hammer.<your-account>.workers.dev (web/wrangler.jsonc).
#
# Needs wrangler, logged in to the Cloudflare account that holds the hammertrade.xyz zone
# (`wrangler whoami`). Wrangler 4 needs Node 22 or newer. If the default `node` is older, point
# NODE22 at a newer one and WRANGLER_JS at wrangler's script:
#
#   NODE22=~/node22/bin/node \
#   WRANGLER_JS=~/node_modules/wrangler/bin/wrangler.js tools/deploy-site.sh
set -euo pipefail
cd "$(dirname "$0")/../web"

npm run build

# The site may only talk to itself, the preview's price feed, and its relayer. If the relayer is
# somewhere other than api.hammertrade.xyz, the security policy has to name that origin instead.
API_URL="${VITE_API_URL:-https://api.hammertrade.xyz}"
API_SCHEME="${API_URL%%://*}"
API_HOST="${API_URL#*://}"
API_HOST="${API_HOST%%/*}"
API_ORIGIN="${API_SCHEME}://${API_HOST}"
grep -v '^#' cloudflare.headers | sed "s#https://api.hammertrade.xyz#${API_ORIGIN}#g" | sed '/./,$!d' > dist/_headers

# The app is one page that draws every address itself. The host is told about each address it
# should answer (a file apiece), so that anything else, above all a script from a build that has
# been replaced, is a plain 404 and never the page. Keep this list in step with ROUTES in
# web/src/lib/route-preload.ts; web/e2e/live-core.mjs checks every page on the published site.
for page in trade jackpot portfolio vault staking leaderboard dashboard stats status docs referrals support; do
  cp dist/index.html "dist/${page}.html"
done
# What an address that is no page gets: the app, which then moves to the trade page.
cp dist/index.html dist/404.html

# PAGES_PROJECT=<name>: publish to that Cloudflare Pages project (the one made by drag and drop in the
# dashboard) instead of the Worker in wrangler.jsonc. Its custom domains stay as they are.
if [ -n "${PAGES_PROJECT:-}" ]; then
  npx --yes wrangler@4 pages deploy dist --project-name "$PAGES_PROJECT" --branch main --commit-dirty=true
elif [ -n "${WRANGLER_JS:-}" ]; then
  "${NODE22:-node}" "$WRANGLER_JS" deploy --config "${WRANGLER_CONFIG:-wrangler.jsonc}"
else
  npx --yes wrangler@4 deploy --config "${WRANGLER_CONFIG:-wrangler.jsonc}"
fi
