#!/usr/bin/env python3
"""Writes Sources/ChronicleKeeperUI/Resources/ItemIcons/item-icons.tsv: the Rexard icon of every item Field Guide's
last import gave one, so a purchase shows the same icon Field Guide does.

Field Guide picks the icons (its import's IconMap) and writes them to
<field-guide>/.build/field-guide-import/icon-map.tsv. This keeps the rows of the equipment packs, keyed as the item
data keys them ("pf2e/<_id>"), with the Rexard file and the name of the small copy scripts/add-artwork.sh makes of
it. toolkit-artwork's rexard/ already holds every icon that table names, so the Artwork submodule has them all.
Run it again after a Field Guide import.

Usage: scripts/item-icons.py [--icon-map FILE]
"""

import argparse
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources/ChronicleKeeperUI/Resources/ItemIcons/item-icons.tsv"
DEFAULT_MAP = ROOT.parent / "field-guide/.build/field-guide-import/icon-map.tsv"
EQUIPMENT_PACKS = {"pf2e.equipment-srd", "sf2e.equipment"}


def main() -> None:
    """Reads Field Guide's icon map and writes the item icon table."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--icon-map", type=Path, default=DEFAULT_MAP)
    arguments = parser.parse_args()
    if not arguments.icon_map.is_file():
        sys.exit(f"Writing the item icons failed: {arguments.icon_map} is missing. Run Field Guide's import first.")
    rows = sorted(item_rows(arguments.icon_map))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="") as file:
        file.write("item\trexard\ticon\n")
        file.writelines(f"{item}\t{rexard}\t{icon_name(rexard)}\n" for item, rexard in rows)
    print(f"Wrote {len(rows)} items' icons ({len({rexard for _, rexard in rows})} pictures) to {OUTPUT}")


def item_rows(icon_map: Path) -> set[tuple[str, str]]:
    """(item id, Rexard path) for each equipment entry that has an icon. Ids are Foundry uuids:
    Compendium.<system>.<pack>.Item.<_id>."""
    rows = set()
    with icon_map.open(encoding="utf-8") as file:
        for row in csv.DictReader(file, delimiter="\t"):
            parts = row["id"].split(".")
            if len(parts) == 5 and parts[3] == "Item" and f"{parts[1]}.{parts[2]}" in EQUIPMENT_PACKS \
                    and row["rexard"]:
                rows.add((f"{parts[1]}/{parts[4]}", row["rexard"]))
    return rows


def icon_name(rexard: str) -> str:
    """One flat file name per picture, since the bundle keeps them in one folder."""
    return rexard.rsplit(".", 1)[0].replace("/", "_").replace(" ", "-") + ".heic"


if __name__ == "__main__":
    main()
