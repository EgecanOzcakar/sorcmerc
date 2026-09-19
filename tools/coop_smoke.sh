#!/usr/bin/env bash
# Co-op, end to end: the relay (wrangler dev), a host and a guest — two real
# headless Godot processes on the real combat screen — playing one fight
# through it. One peer "crashes" partway (quits) and is started again on the
# same room code, so the second half is also a rejoin. Passes when both peers
# finish with the same state hash.
#   tools/coop_smoke.sh            the guest crashes; it came in by env var
#   tools/coop_smoke.sh host       the host crashes and rejoins (host:CODE)
#   tools/coop_smoke.sh game       the guest crashes; it came in through the
#                                  title's Play together → Join (game.gd)
#   tools/coop_smoke.sh drop       nobody crashes; the host's socket is closed
#                                  under it mid-fight and comes back
# Needs godot on PATH and npx wrangler.
set -uo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-guest}"
PORT=8799
CODE=$(tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 6)
export SORCMERC_RELAY="ws://127.0.0.1:$PORT" SORCMERC_FAST=1
LOG=$(mktemp -d)
DRIVE="godot --headless --path . -s tests/drive_coop.gd"

(cd tools/coop-relay && npx wrangler dev --port $PORT --local >"$LOG/relay" 2>&1) &
# npx -> node -> workerd: killing the job leaves the rest, so name them instead
trap 'pkill -f "wrangler dev --port $PORT" 2>/dev/null; pkill workerd 2>/dev/null' EXIT
for _ in $(seq 60); do grep -q "Ready on" "$LOG/relay" && break; sleep 1; done
grep -q "Ready on" "$LOG/relay" || { echo "relay did not start:"; tail -5 "$LOG/relay"; exit 2; }
# "Ready" comes a beat before workerd answers, and wrangler may reload once
# more on a fresh state dir; a plain GET gets 426 from the Worker when it is up.
for _ in $(seq 30); do [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/room/ABC234?role=host")" = 426 ] && break; sleep 1; done
sleep 2

# The peer that crashes runs in the foreground so its exit code can be seen;
# the other runs behind it.
case "$MODE" in
	drop)
		SORCMERC_COOP="$CODE" $DRIVE >"$LOG/guest" 2>&1 &
		OTHER=$!
		sleep 2
		SORCMERC_COOP="host:$CODE" SORCMERC_COOP_DROP_AT=8 $DRIVE >"$LOG/host" 2>&1 ;;
	host)
		SORCMERC_COOP="$CODE" $DRIVE >"$LOG/guest" 2>&1 &
		OTHER=$!
		sleep 2
		SORCMERC_COOP="host:$CODE" SORCMERC_COOP_QUIT_AFTER=6 $DRIVE >"$LOG/host1" 2>&1
		if [ $? -eq 3 ]; then
			echo "host quit after 6 presses; rejoining room $CODE"
			SORCMERC_COOP="host:$CODE" $DRIVE >"$LOG/host2" 2>&1
		fi ;;
	*)
		SORCMERC_COOP="host:$CODE" $DRIVE >"$LOG/host" 2>&1 &
		OTHER=$!
		sleep 2
		VIA=""; [ "$MODE" = game ] && VIA=game
		SORCMERC_COOP="$CODE" SORCMERC_COOP_VIA=$VIA SORCMERC_COOP_QUIT_AFTER=4 $DRIVE >"$LOG/guest1" 2>&1
		if [ $? -eq 3 ]; then
			echo "guest quit after 4 presses; rejoining room $CODE"
			SORCMERC_COOP="$CODE" SORCMERC_COOP_VIA=$VIA $DRIVE >"$LOG/guest2" 2>&1
		fi ;;
esac
wait $OTHER
grep -h "^host:\|^guest:" "$LOG"/host* "$LOG"/guest* 2>/dev/null
grep -h "DESYNC\|wedged\|SCRIPT ERROR" "$LOG"/host* "$LOG"/guest* 2>/dev/null
H=$(grep -oh "hash=-\?[0-9]*" "$LOG"/host* | tail -1)
G=$(grep -oh "hash=-\?[0-9]*" "$LOG"/guest* | tail -1)
if [ -n "$H" ] && [ "$H" = "$G" ]; then echo "coop smoke ($MODE): OK — both peers ended on $H"; exit 0; fi
echo "coop smoke ($MODE): FAIL (host $H, guest $G); logs in $LOG"; exit 1
