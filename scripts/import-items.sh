#!/bin/sh
# Writes the item price list the purchase ledger searches, Resources/Items/items.json, with the ORC and OGL
# licenses it is used under. The repository leaves them out; a store build fails without them.
#
# PF2E_REPO  a pf2e system repository to read instead of the release in pf2e.release, which is fetched into
#            build/pf2e (scripts/fetch-pf2e.sh); release builds always use that release
set -eu

cd "$(dirname "$0")/.."

if [ -z "${PF2E_REPO:-}" ]; then
    scripts/fetch-pf2e.sh build/pf2e
    PF2E_REPO=build/pf2e
else
    echo "Reading $PF2E_REPO; release builds read $(cut -d ' ' -f 2- pf2e.release) instead." >&2
fi

swift build -c release --product ItemPrices
"$(swift build -c release --show-bin-path)/ItemPrices" --pf2e "$PF2E_REPO" \
    --out Sources/ChronicleKeeperKit/Resources/Items
