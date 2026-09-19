#!/usr/bin/env bash
# The co-op spike, end to end: the relay (wrangler dev), a host and a guest —
# two real headless Godot processes on the real combat screen — playing one
# fight through it. The guest "crashes" partway (quits) and is started again
# with the same room code, so the second half is also a rejoin. Passes when
# both peers finish with the same state hash.
#   tools/coop_smoke.sh            (needs godot on PATH and npx wrangler)
set -uo pipefail
cd "$(dirname "$0")/.."
PORT=8799
CODE=$(tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 6)
export SORCMERC_RELAY="ws://127.0.0.1:$PORT" SORCMERC_FAST=1
LOG=$(mktemp -d)

(cd tools/coop-relay && npx wrangler dev --port $PORT --local >"$LOG/relay" 2>&1) &
# npx -> node -> workerd: killing the job leaves the rest, so name them instead
trap 'pkill -f "wrangler dev --port $PORT" 2>/dev/null; pkill workerd 2>/dev/null' EXIT
for _ in $(seq 60); do grep -q "Ready on" "$LOG/relay" && break; sleep 1; done
grep -q "Ready on" "$LOG/relay" || { echo "relay did not start:"; tail -5 "$LOG/relay"; exit 2; }

SORCMERC_COOP="host:$CODE" godot --headless --path . -s tests/drive_coop.gd >"$LOG/host" 2>&1 &
HOST=$!
sleep 2
SORCMERC_COOP="$CODE" SORCMERC_COOP_QUIT_AFTER=4 godot --headless --path . -s tests/drive_coop.gd >"$LOG/guest1" 2>&1
if [ $? -eq 3 ]; then
	echo "guest quit after 4 presses; rejoining room $CODE"
	SORCMERC_COOP="$CODE" godot --headless --path . -s tests/drive_coop.gd >"$LOG/guest2" 2>&1
fi
wait $HOST
grep -h "^host:\|^guest:" "$LOG/host" "$LOG/guest1" "$LOG/guest2" 2>/dev/null
grep -h "DESYNC\|wedged\|SCRIPT ERROR" "$LOG"/host "$LOG"/guest* 2>/dev/null
H=$(grep -o "hash=-\?[0-9]*" "$LOG/host" | tail -1)
G=$(grep -oh "hash=-\?[0-9]*" "$LOG"/guest* | tail -1)
if [ -n "$H" ] && [ "$H" = "$G" ]; then echo "coop smoke: OK — both peers ended on $H"; exit 0; fi
echo "coop smoke: FAIL (host $H, guest $G); logs in $LOG"; exit 1
