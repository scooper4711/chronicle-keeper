#!/bin/sh
# Prints the identifier of a simulator of the given kind (iPad or iPhone): the one named by SIMULATOR, or
# otherwise one of that kind on the newest installed iOS version. Prints nothing when there is none.
#
#   scripts/simulator-id.sh iPad|iPhone
set -eu

KIND="${1:?Usage: scripts/simulator-id.sh iPad|iPhone}"

xcrun simctl list devices available --json | KIND="$KIND" /usr/bin/python3 -c '
import json
import os
import sys

kind = os.environ["KIND"]
wanted = os.environ.get("SIMULATOR", "")
runtimes = json.load(sys.stdin)["devices"]


def version(runtime):
    digits = runtime.rsplit("iOS-", 1)[-1].split("-")
    return [int(part) for part in digits if part.isdigit()]


candidates = [
    (version(runtime), device)
    for runtime, devices in runtimes.items() if "iOS" in runtime
    for device in devices if device["name"].startswith(kind)
    and (not wanted or device["name"] == wanted)
]
candidates.sort(key=lambda pair: pair[0])
print(candidates[-1][1]["udid"] if candidates else "")
'
