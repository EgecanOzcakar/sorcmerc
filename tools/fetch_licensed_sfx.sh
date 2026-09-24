#!/bin/sh
# Keep assets/audio/sfx/licensed/ in step with the private
# EgecanOzcakar/sorcmerc-licensed-audio for whoever can read it. That folder is
# gitignored: its real recordings may ship inside the game but not sit in this
# public repo as sound files (tools/import_licensed_sfx.py says why and how they
# are built), and core/audio.gd plays them over the committed generated takes.
# Without access this does nothing and the game plays the generated takes.
#
# Run by .githooks/_reimport.sh after every pull and checkout, before the
# import, so Godot picks up whatever changed. Never fails: a hook must not
# block the pull it runs after. The release workflow does the same with a
# deploy key (.github/workflows/release.yml, "Fetch the licensed sfx").
#
# A licensed/ folder that holds files but is not a checkout (built locally by
# tools/import_licensed_sfx.py) is left alone.
cd "$(git rev-parse --show-toplevel)" || exit 0
# A hook runs with GIT_DIR and friends pointing at the outer repo; a nested
# `git -C licensed pull` would otherwise act on that repo, not the checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
export GIT_TERMINAL_PROMPT=0     # no access means no password prompt either
DIR=assets/audio/sfx/licensed
REPO=${LICENSED_AUDIO_REPO:-https://github.com/EgecanOzcakar/sorcmerc-licensed-audio.git}
if [ -d "$DIR/.git" ]; then
	git -C "$DIR" pull -q --ff-only >/dev/null 2>&1
elif [ -z "$(ls -A "$DIR" 2>/dev/null)" ]; then
	rmdir "$DIR" 2>/dev/null
	git clone -q --depth 1 "$REPO" "$DIR" >/dev/null 2>&1
fi
exit 0
