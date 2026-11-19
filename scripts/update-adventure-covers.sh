#!/bin/sh
# Rewrites the table of covers the app ships with, from Warhorn's catalog (warhorn.net).
#
# The table holds the adventures a session names without a scenario number: standalone adventures, Adventure Path
# volumes, modules, one-shots, and the intros that only the catalog numbers. The app finds their covers here and
# asks Warhorn only for numbered adventures (see CoverTable and CoverFinder). Run it when Paizo sanctions another
# such adventure or a season gets its intro, then commit the result.
#
#   scripts/update-adventure-covers.sh
#
# Needs curl and jq. Makes about thirty requests; Warhorn allows an address 300 in five minutes.
set -eu

cd "$(dirname "$0")/.."

OUT="Sources/ChronicleKeeperKit/Resources/adventure-covers.json"
ENDPOINT="https://warhorn.net/graphql"
# Warhorn starts a scenario's name with its campaign ("PFS2 6-04: ...") and any other adventure's with the game
# ("PF2 Adventure: ..."). The catalog can't be listed by campaign, so each of these is searched for instead.
PREFIXES="PFS1 PFS2 SFS1 SFS2 PF1 PF2 SF1 SF2"
LONGEST_LIST=40
# shellcheck disable=SC2016 # $query and $after are GraphQL variables, not the shell's.
QUERY='query Covers($query: String, $after: String) {
  globalScenarios(query: $query, first: 100, after: $after) {
    nodes { name isCustom coverArtUrl campaign { code } }
    pageInfo { hasNextPage endCursor }
  }
}'

# The servers a cover may be on, as CoverHost.isAllowed says: Paizo, the folder of Paizo's store on BigCommerce, and
# Warhorn (imgix and its S3 buckets).
PAIZO='([a-z0-9-]+\.)?paizo\.com'
PAIZO_STORE='cdn11\.bigcommerce\.com/s-e0sdfpgiwh'
WARHORN='warhorn\.imgix\.net|warhorn[a-z0-9.-]*\.s3[a-z0-9.-]*\.amazonaws\.com'
HOSTS="^https://($PAIZO|$PAIZO_STORE|$WARHORN)/"

# The adventures with a cover on those servers that the four campaigns publish, without the ones the app looks up
# by number: season scenarios (but not their intros, which the Sessions tab doesn't number), numbered quests and
# bounties.
# shellcheck disable=SC2016 # $hosts is a jq variable, not the shell's.
ROWS='
  select(.isCustom | not)
  | select(.campaign.code // "" | test("^[PS]FS[12]$"))
  | select((.coverArtUrl // "") | test($hosts))
  | select(.name | test("Scenario Pending|Infinite Scenario") | not)
  | select(.name | (test("^[PS]FS[12] [0-9]+-[0-9]+") and (test(": Intro:") | not)) | not)
  | select(.name | test("Quest[^#]*#[0-9]+|Bounty [0-9]+") | not)
  | {campaign: .campaign.code, name, cover: .coverArtUrl}
'

# Prints one page of the scenarios whose name contains $1, after the cursor $2 (empty for the first page).
page() {
    body="$(jq -n --arg query "$QUERY" --arg text "$1" --arg after "$2" \
        '{query: $query, variables: {query: $text, after: (if $after == "" then null else $after end)}}')"
    curl --silent --show-error --fail \
        --header "Content-Type: application/json" --header "Accept: application/json" \
        --user-agent "ChronicleKeeper cover table script" \
        --data "$body" "$ENDPOINT"
}

# Prints every scenario whose name contains $1, one JSON object to a line.
list() {
    after=""
    pages=0
    while [ "$pages" -lt "$LONGEST_LIST" ]; do
        reply="$(page "$1" "$after")"
        if ! echo "$reply" | jq -e '.data.globalScenarios' >/dev/null; then
            echo "Listing Warhorn's \"$1\" scenarios failed: $(echo "$reply" | jq -c '.errors // .')" >&2
            exit 1
        fi
        echo "$reply" | jq -c '.data.globalScenarios.nodes[]'
        pages=$((pages + 1))
        if [ "$(echo "$reply" | jq -r '.data.globalScenarios.pageInfo.hasNextPage')" != "true" ]; then
            return
        fi
        after="$(echo "$reply" | jq -r '.data.globalScenarios.pageInfo.endCursor')"
    done
    echo "Listing Warhorn's \"$1\" scenarios failed: more than $LONGEST_LIST pages" >&2
    exit 1
}

nodes="$(mktemp)"
trap 'rm -f "$nodes"' EXIT
for prefix in $PREFIXES; do
    list "$prefix" >> "$nodes"
done

mkdir -p "$(dirname "$OUT")"
# One row to a line, in a fixed order, so that a change shows up as the rows that changed.
{
    echo "["
    jq -c --arg hosts "$HOSTS" "$ROWS" "$nodes" | jq -s -r 'unique_by([.campaign, .name]) | map(tojson) | join(",\n")'
    echo "]"
} > "$OUT"

echo "Wrote $(jq length "$OUT") covers to $OUT"
