#!/bin/sh
# Writes the Rexard art the app shows into the package's resources: the rosette beside Fame, and the item icons
# (64-pixel HEIC copies of the pictures ItemIcons/item-icons.tsv names; see scripts/item-icons.py). The art is
# licensed for use inside the app only, so it is never committed (.gitignore); without it the app draws symbols.
#
# REXARD_PACKS  folder holding the Rexard packs. When it is named, the art must be there, as a release requires.
#               Otherwise the script looks in Artwork/rexard (the private submodule) and ../rexard-packs (the
#               full packs), and leaves the app without the art when neither holds it.
set -eu

cd "$(dirname "$0")/.."

# The path inside the packs. toolkit-artwork's scripts/sync.py reads it from this file to know what to keep.
FAME="fairytaleiconsmegapack/TrophyIcons/TrophyIcons_transparent/TrophyIcons_32_t.png"
FACTIONS="Sources/ChronicleKeeperUI/Resources/Factions"

if [ -n "${REXARD_PACKS:-}" ]; then
    PACKS="$REXARD_PACKS"
    [ -f "$PACKS/$FAME" ] || { echo "Adding the artwork failed: $PACKS/$FAME is missing." >&2; exit 1; }
else
    PACKS=""
    for folder in Artwork/rexard ../rexard-packs; do
        if [ -f "$folder/$FAME" ]; then
            PACKS="$folder"
            break
        fi
    done
fi

if [ -z "$PACKS" ]; then
    echo "No Rexard packs here, so the app shows a symbol for Fame."
    exit 0
fi
# Half the picture's size, as every build so far has carried it.
sips -Z 128 "$PACKS/$FAME" --out "$FACTIONS/fame.png" >/dev/null
echo "Added the Fame rosette from $PACKS"

# Each item icon once, skipping those already made. A picture missing from the packs leaves its items a symbol.
ICONS="Sources/ChronicleKeeperUI/Resources/ItemIcons"
made=0
missing=0
tail -n +2 "$ICONS/item-icons.tsv" | cut -f 2,3 | sort -u > "${TMPDIR:-/tmp}/chronicle-keeper-icons.$$"
while IFS="$(printf '\t')" read -r picture icon; do
    [ -f "$ICONS/$icon" ] && continue
    if [ -f "$PACKS/$picture" ]; then
        sips -Z 64 -s format heic "$PACKS/$picture" --out "$ICONS/$icon" >/dev/null
        made=$((made + 1))
    else
        missing=$((missing + 1))
    fi
done < "${TMPDIR:-/tmp}/chronicle-keeper-icons.$$"
rm -f "${TMPDIR:-/tmp}/chronicle-keeper-icons.$$"
echo "Made $made item icons from $PACKS ($missing pictures not in the packs)."
