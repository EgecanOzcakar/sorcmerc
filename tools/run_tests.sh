#!/usr/bin/env bash
#
# The whole headless suite, in one command — what CI runs (.github/workflows/
# tests.yml) and what a contributor runs locally, so "green on my machine" and
# "green on the PR" are the same claim.
#
#   tools/run_tests.sh                    # checks + unit tests + drive tests
#   tools/run_tests.sh --unit             # just tests/test_*.gd
#   tools/run_tests.sh --drive            # just tests/drive_*.gd (the robots)
#   tools/run_tests.sh tests/test_story.gd tests/test_quest.gd   # just these
#   tools/run_tests.sh --list             # print what would run, run nothing
#
#   GODOT=/path/to/godot tools/run_tests.sh     # default: `godot` on PATH
#   TEST_TIMEOUT=1200 tools/run_tests.sh        # per-test seconds, default 900
#
# Three things this knows that a bare `godot -s tests/foo.gd` loop does not:
#
#  1. Assets must be imported first. A script that preloads a texture cannot
#     even COMPILE without .godot/imported/, so on a fresh checkout half the
#     suite fails with parse errors that have nothing to do with the tests.
#     Godot's own --import is incremental, so doing it every run is nearly free
#     once it has been done once. (--no-import skips it.)
#
#  2. The verdict is the EXIT CODE, never the output. Most tests print
#     "N passed, M failed", but some print "OK" and some print a one-line
#     summary of their own; all of them quit(1) on failure.
#
#  3. A test that fails an assert() HANGS — the SceneTree never reaches its
#     quit(), so the process sits in the main loop forever. Every test
#     therefore runs under `timeout`, and a timeout is a failure, not a skip.
set -uo pipefail

GODOT="${GODOT:-godot}"
TEST_TIMEOUT="${TEST_TIMEOUT:-900}"
# The two the drive robots have always wanted: a pinned seed (so a failure is
# the same failure next run) and FAST, which zeroes UI tween timing and skips
# the cosmetic-only systems there is nothing to assert on headless.
export SORCMERC_SEED="${SORCMERC_SEED:-5}"
export SORCMERC_FAST="${SORCMERC_FAST:-1}"

cd "$(dirname "$0")/.." || exit 2
ROOT="$PWD"

run_checks=1
run_unit=1
run_drive=1
do_import=1
list_only=0
explicit=()

while [ $# -gt 0 ]; do
	case "$1" in
		--unit)       run_checks=1; run_unit=1; run_drive=0 ;;
		--drive)      run_checks=0; run_unit=0; run_drive=1 ;;
		--checks)     run_checks=1; run_unit=0; run_drive=0 ;;
		--no-import)  do_import=0 ;;
		--list)       list_only=1 ;;
		-h|--help)    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*)           echo "unknown option: $1" >&2; exit 2 ;;
		*)            explicit+=("$1") ;;
	esac
	shift
done

# --- what to run ------------------------------------------------------------

files=()
if [ ${#explicit[@]} -gt 0 ]; then
	files=("${explicit[@]}")
else
	[ "$run_checks" = 1 ] && files+=("tests/check_scripts.gd")
	if [ "$run_unit" = 1 ]; then
		while IFS= read -r f; do files+=("$f"); done < <(ls tests/test_*.gd)
	fi
	if [ "$run_drive" = 1 ]; then
		while IFS= read -r f; do files+=("$f"); done < <(ls tests/drive_*.gd)
	fi
fi

if [ ${#files[@]} -eq 0 ]; then
	echo "nothing to run" >&2
	exit 2
fi

if [ "$list_only" = 1 ]; then
	printf '%s\n' "${files[@]}"
	exit 0
fi

# Checked here rather than at the top so --list and --help work anywhere.
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "godot not found (tried '$GODOT'). Set GODOT=/path/to/godot." >&2
	exit 2
fi

# --- import -----------------------------------------------------------------

if [ "$do_import" = 1 ]; then
	echo "== importing assets (incremental) =="
	# Never fails the run: import prints errors for things that do not matter
	# headless (a missing display, an audio driver), and the checks below are
	# the real verdict on whether the project is loadable.
	"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1
fi

# --- run --------------------------------------------------------------------

pass=0
fail=0
failed_names=()
started=$(date +%s)

for f in "${files[@]}"; do
	t0=$(date +%s)
	out=$(timeout --kill-after=10s "$TEST_TIMEOUT" \
		"$GODOT" --headless --path "$ROOT" -s "$f" 2>&1)
	code=$?
	t1=$(date +%s)
	secs=$(( t1 - t0 ))
	# Whatever the test chose to say about itself, for the one-line report: its
	# last real line of output. Every test ends with a summary of its own, but
	# they do not agree on a format, so this takes the line rather than a shape.
	summary=$(printf '%s\n' "$out" \
		| grep -vE "^(ERROR|WARNING|SCRIPT ERROR)|^ +(at:|\[[0-9]+\])|^Godot Engine v" \
		| grep -E "[A-Za-z]" | tail -1)
	if [ "$code" -eq 0 ]; then
		pass=$(( pass + 1 ))
		printf 'ok    %4ds  %-36s %s\n' "$secs" "$f" "$summary"
	else
		fail=$(( fail + 1 ))
		failed_names+=("$f")
		if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
			printf 'FAIL  %4ds  %-36s TIMED OUT after %ss (a failed assert() hangs)\n' \
				"$secs" "$f" "$TEST_TIMEOUT"
		else
			printf 'FAIL  %4ds  %-36s exit %d  %s\n' "$secs" "$f" "$code" "$summary"
		fi
		echo "----- last 25 lines of $f -----"
		printf '%s\n' "$out" | tail -25
		echo "-------------------------------"
	fi
done

elapsed=$(( $(date +%s) - started ))
echo
echo "== $pass passed, $fail failed, ${elapsed}s =="
if [ "$fail" -gt 0 ]; then
	printf 'failed: %s\n' "${failed_names[*]}"
	exit 1
fi
