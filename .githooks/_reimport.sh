#!/bin/sh
# Shared body for post-merge/post-checkout. Godot's own --import is already
# incremental (it only touches files whose source changed since the last
# import), so running it on every pull/checkout is cheap when nothing moved
# and free of the "cannot open .ctex/.fontdata" surprise when something did.
cd "$(git rev-parse --show-toplevel)" || exit 0
GODOT_BIN="${GODOT_BIN:-godot}"
command -v "$GODOT_BIN" >/dev/null 2>&1 || exit 0   # not installed here (e.g. CI) -- nothing to do
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1
exit 0   # never block the pull/checkout itself on an import hiccup
