#!/usr/bin/env python3
"""Writes the census of chronicle sheet formats the sheet reader is tested against.

For every blank chronicle in a pfs-chronicle-generator checkout (Pathfinder Society and Starfinder Society, second
edition), it records where the sheet prints its labels and where a value is written: the labels from the PDF's own
text, the value boxes from the generator's layout for that sheet. The result holds titles, labels and positions
only, none of the sheets' prose, so it can be committed.

    PFS_TOOLS=~/git/pfs-tools "$PFS_TOOLS/chronicle2layout/.venv/bin/python" scripts/chronicle-format-census.py

Needs PyMuPDF (the chronicle2layout checkout's virtual environment has it). Run it when the generator gains
chronicles, then commit Tests/ChronicleKeeperKitTests/Fixtures/chronicle-formats.json.
"""

import glob
import json
import os
import re
import sys

import fitz

OUT = "Tests/ChronicleKeeperKitTests/Fixtures/chronicle-formats.json"
# The generator's name for each value the reader looks for; the first one a layout has is used.
VALUE_PARAMETERS = {
    "xp": ["xp_gained"],
    "funds": ["currency_gained", "gp_gained"],
    "player": ["societyid", "societyid.player"],
    "character": ["char_number", "char_number_short", "societyid.char"],
    "eventCode": ["eventcode"],
}
# Where the sheet's own short printing is kept from: the reward column and the strips at the top and bottom.
REWARD_COLUMN_LEFT = 0.74
TOP_STRIP_BOTTOM = 0.20
BOTTOM_STRIP_TOP = 0.86
LONGEST_PRINTED_LINE = 45


def main():
    generator = os.path.join(os.path.expanduser(os.environ.get("PFS_TOOLS", "~/git/pfs-tools")),
                             "pfs-chronicle-generator")
    layouts = load_layouts(os.path.join(generator, "assets", "layouts"))
    chronicles = os.path.join(generator, "assets", "chronicles")
    sheets = [describe(pdf, chronicles, layouts) for pdf in sorted(glob.glob(f"{chronicles}/*/*/*.pdf"))]
    with open(OUT, "w", encoding="utf-8") as out:
        json.dump({"sheets": sheets}, out, ensure_ascii=False, separators=(",", ":"))
        out.write("\n")
    disagreeing = [sheet["sheet"] for sheet in sheets if sheet.get("layoutDisagrees")]
    unlabeled = [sheet["sheet"] for sheet in sheets if sheet.get("labelsNotInText")]
    print(f"{len(sheets)} sheets written to {OUT}")
    print(f"layouts that disagree with their sheet: {disagreeing}")
    print(f"sheets whose labels aren't text: {unlabeled}")
    for sheet in sheets:
        if sheet.get("misplaced"):
            print(f"values the layout puts over another label: {sheet['sheet']}: {sheet['misplaced']}")


def describe(pdf, chronicles, layouts):
    """One sheet: its name, the code its file name gives it, its printing and its value boxes."""
    page = fitz.open(pdf)[0]
    name = os.path.relpath(pdf, chronicles)[: -len(".pdf")]
    printed = printed_lines(page)
    sheet = {"sheet": name, "code": code_from_file_name(os.path.basename(name)), "printed": printed}
    values = value_boxes(os.path.basename(pdf), layouts)
    if not has_label(printed, "xp gained"):
        # The labels are drawn as shapes, not text: nothing to place a value against.
        sheet["labelsNotInText"] = True
    elif values and layout_agrees(printed, values):
        sheet["values"] = {name: box for name, box in values.items() if is_over_its_label(name, box, printed)}
        sheet["misplaced"] = sorted(set(values) - set(sheet["values"]))
        if not sheet["misplaced"]:
            del sheet["misplaced"]
    elif values:
        sheet["layoutDisagrees"] = True
    return sheet


def code_from_file_name(name):
    """ "5-11-…" is "5-11", "Q22-…" is "Quest 22", "B19-…" is "Bounty 19"; anything else has no code."""
    if match := re.match(r"(\d+)-(\d+)", name):
        return f"{int(match[1])}-{match[2]}"
    if match := re.match(r"Q(\d+)", name):
        return f"Quest {match[1]}"
    if match := re.match(r"B(\d+)", name):
        return f"Bounty {match[1]}"
    return None


# MARK: - The sheet's printing


def printed_lines(page):
    """The short lines printed in the reward column and the two strips, as [text, x, y, width, height]:
    fractions of the page, y measured from the top."""
    width, height = page.rect.width, page.rect.height
    lines = []
    for text, box in segments(page):
        x, y = box[0] / width, box[1] / height
        in_kept_area = x >= REWARD_COLUMN_LEFT or y <= TOP_STRIP_BOTTOM or y >= BOTTOM_STRIP_TOP
        if in_kept_area and len(text) <= LONGEST_PRINTED_LINE:
            lines.append([text, round(x, 4), round(y, 4), round((box[2] - box[0]) / width, 4),
                          round((box[3] - box[1]) / height, 4)])
    return sorted(lines, key=lambda line: (line[2], line[1]))


def segments(page):
    """Runs of words on one line with no wide gap between them, as text recognition would give them."""
    runs = []
    previous = None
    for x0, y0, x1, y1, word, block, line, _ in page.get_text("words"):
        same_run = previous and previous[0] == (block, line) and x0 - previous[1] < 0.9 * (y1 - y0)
        if same_run:
            text, box = runs[-1]
            runs[-1] = (f"{text} {word}", (box[0], min(box[1], y0), x1, max(box[3], y1)))
        else:
            runs.append((word, (x0, y0, x1, y1)))
        previous = ((block, line), x1)
    return runs


# MARK: - The generator's value boxes


def load_layouts(folder):
    layouts = {}
    for file in glob.glob(f"{folder}/**/*.json", recursive=True):
        with open(file, encoding="utf-8") as source:
            layout = json.load(source)
        layouts[layout["id"]] = layout
    return layouts


def value_boxes(pdf_name, layouts):
    """Where the sheet's own layout writes each value, as [x, y, width, height]; empty without a layout."""
    layout = layout_for(pdf_name, layouts)
    if layout is None:
        return {}
    chain = ancestry(layout, layouts)
    canvases, presets, parameters = {}, {}, {}
    for ancestor in chain:
        canvases.update(ancestor.get("canvas") or {})
        presets.update(ancestor.get("presets") or {})
    for ancestor in chain:
        collect_parameters(ancestor.get("content"), presets, parameters)
    boxes = {}
    for value, names in VALUE_PARAMETERS.items():
        entry = next((parameters[name] for name in names if name in parameters), None)
        if entry:
            boxes[value] = page_box(entry, canvases)
    return boxes


def layout_for(pdf_name, layouts):
    """The most specific layout that names this PDF as its chronicle."""
    named = [layout for layout in layouts.values()
             if os.path.basename(layout.get("defaultChronicleLocation") or "") == pdf_name]
    return max(named, key=lambda layout: len(ancestry(layout, layouts)), default=None)


def ancestry(layout, layouts):
    """The layout's parents, the root first, and then the layout itself."""
    chain = []
    while layout:
        chain.append(layout)
        layout = layouts.get(layout.get("parent"))
    return chain[::-1]


def collect_parameters(content, presets, parameters):
    """Every content entry that writes a parameter, by the parameter's name; a later entry replaces an earlier."""
    for entry in content or []:
        if not isinstance(entry, dict):
            continue
        resolved = with_presets(entry, presets)
        value = resolved.get("value")
        if isinstance(value, str) and value.startswith("param:") and "x" in resolved:
            parameters[value[len("param:"):]] = resolved
        nested = entry.get("content")
        for part in [nested] if isinstance(nested, list) else list((nested or {}).values()):
            if isinstance(part, list):
                collect_parameters(part, presets, parameters)


def with_presets(entry, presets, seen=()):
    resolved = {}
    for name in entry.get("presets") or []:
        if name in presets and name not in seen:
            resolved.update(with_presets(presets[name], presets, seen + (name,)))
    resolved.update({key: value for key, value in entry.items() if key != "presets"})
    return resolved


def page_box(entry, canvases):
    """An entry's box, given in percent of its canvas, as fractions of the page."""
    x, y, x2, y2 = entry["x"], entry["y"], entry["x2"], entry["y2"]
    canvas = entry.get("canvas")
    while canvas in canvases:
        frame = canvases[canvas]
        width, height = frame["x2"] - frame["x"], frame["y2"] - frame["y"]
        x, x2 = frame["x"] + x * width / 100, frame["x"] + x2 * width / 100
        y, y2 = frame["y"] + y * height / 100, frame["y"] + y2 * height / 100
        canvas = frame.get("parent")
    return [round(x / 100, 4), round(y / 100, 4), round((x2 - x) / 100, 4), round((y2 - y) / 100, 4)]


def layout_agrees(printed, values):
    """Whether the layout writes the XP in the box the sheet's own printing gives it: above "XP Gained" on a sheet
    that prints "Final XP", below it otherwise, with no other label between the label and the far edge of the
    value. A layout that doesn't was made for another sheet's positions."""
    if "xp" not in values:
        return True
    label = next(line for line in printed if squashed(line[0]).startswith("xp gained"))
    label_middle = label[2] + label[4] / 2
    value_top, value_bottom = values["xp"][1], values["xp"][1] + values["xp"][3]
    if ((value_top + value_bottom) / 2 < label_middle) != has_label(printed, "final xp"):
        return False
    top, bottom = min(label_middle, value_top), max(label_middle, value_bottom)
    others = [line[2] + line[4] / 2 for line in printed if line is not label and is_reward_label(line)]
    return not any(top < middle < bottom for middle in others)


STRIP_LABELS = {"player": "organized play #", "character": "character #", "eventCode": "event code"}


def is_over_its_label(name, box, printed):
    """Whether a value of the top or bottom strip is written over its own label, as every sheet prints them. One
    that isn't was given another box's place in the layout."""
    if name not in STRIP_LABELS:
        return True
    label = next((line for line in printed if squashed(line[0]) == STRIP_LABELS[name]), None)
    if label is None:
        return False
    overlaps = box[0] < label[1] + label[3] and label[1] < box[0] + box[2]
    return overlaps and box[1] < label[2]


REWARD_LABEL = re.compile(r"(xp|gp|gold|credits|fame|income|sold|^total)", re.IGNORECASE)


def is_reward_label(line):
    """A horizontal line of the reward column that names a box."""
    text, x, _, width, height = line
    return x >= REWARD_COLUMN_LEFT and width > height and bool(REWARD_LABEL.search(text)) and len(text) > 4


def has_label(printed, label):
    return any(squashed(line[0]).startswith(label) for line in printed)


def squashed(text):
    return re.sub(r"\s+", " ", text).strip().lower()


if __name__ == "__main__":
    sys.exit(main())
