#!/bin/sh
# Writes the Rexard art the app shows into the package's resources: the rosette beside Fame. The art is licensed
# for use inside the app only, so it is never committed (.gitignore); without it the app draws a symbol instead.
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
