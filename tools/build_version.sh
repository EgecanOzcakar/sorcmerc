#!/usr/bin/env bash
#
# The one place that decides what a build calls itself.
#
#   tools/build_version.sh release            # on a v* tag  -> 0.2.1
#   tools/build_version.sh playtest           # on a test* tag -> 0.2.2-playtest.7+g1a2b3c4
#   tools/build_version.sh dev                # on master    -> 0.2.2-dev.7+g1a2b3c4
#   tools/build_version.sh --self-test        # exercise all of the above, run nothing else
#
# Printed on stdout, one line, nothing else — .github/workflows/release.yml
# stamps it into project.godot's application/config/version (which is what
# core/bug_report.gd puts on every report) and hands the same string to butler
# as the itch.io build's user version. One string, so "it happens on
# 0.2.2-dev.7" names a commit on the build page and on the report alike.
#
# The convention, and why it is this one:
#
#   * Every channel prints valid SemVer 2.0.0. The old scheme printed the raw
#     ref name — `v0.1.0`, `test-2026-09-11`, `dev-47-71adb56` — three shapes
#     that sort against each other only by accident. These sort by precedence:
#     0.1.0 < 0.2.2-dev.7 < 0.2.2-playtest.7 < 0.2.2.
#   * A pre-release build is named for the release it is HEADING TOWARD, not
#     the one behind it: eleven commits past v0.2.1 is 0.2.2-dev.11, not
#     0.2.1-something, because a 0.2.1-* would sort BELOW the 0.2.1 it is
#     already newer than. If the nearest tag is itself a pre-release
#     (v0.3.0-rc.1), the release it heads toward is 0.3.0 and nothing is bumped.
#   * The distance (commits since that tag) is the monotonic part, so two dev
#     builds order correctly without asking a CI run number — which the old
#     dev- scheme used, and which says nothing about the code.
#   * The short sha rides in SemVer build metadata (+g1a2b3c4, `git describe`'s
#     spelling), because that is what a bug report needs and what precedence
#     is required to ignore.
#   * A playtest build is versioned by its commit, not by its tag name. Playtest
#     tags are labels for humans ("test-2026-09-11") and make poor versions;
#     the tag still names the run in the Actions log.
#
# With no v* tag in history yet, there is no released version to bump from, so
# the base is the version the project is working toward (BASE_WHEN_UNTAGGED,
# kept in step with project.godot's own placeholder) and it is NOT bumped:
# a fresh repo's master builds are 0.1.0-dev.N, heading toward a first 0.1.0.
set -uo pipefail

# The version a first release is expected to carry, used only until a v* tag
# exists. project.godot ships "<this>-dev" for a run from source; keep the two
# in step, and after the first v* tag neither one matters again.
BASE_WHEN_UNTAGGED="0.1.0"

# SemVer 2.0.0's own grammar, verbatim (semver.org's suggested regex, minus its
# capture groups). A malformed v* tag is a failed run, not a build published to
# itch.io under a version nothing can compare.
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'

die() { echo "build_version: $*" >&2; exit 2; }

# --- the pieces -----------------------------------------------------------

# The v* tag nearest to HEAD, or empty if history carries none. --match keeps
# test* and any other tag out of it: only releases are version anchors.
nearest_release_tag() {
	git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true
}

# 1.2.3 -> 1.2.4; 1.2.3-rc.1 -> 1.2.3 (the release that pre-release heads for).
next_version() {
	local v="$1"
	case "$v" in
		*-*) echo "${v%%-*}" ;;
		*)
			local major minor patch
			IFS=. read -r major minor patch <<<"$v"
			echo "${major}.${minor}.$((patch + 1))"
			;;
	esac
}

# --- the three channels ---------------------------------------------------

version_for() {
	local channel="$1" tag="${2:-}"

	if [ "$channel" = "release" ]; then
		[ -n "$tag" ] || die "the release channel needs the tag it was triggered by"
		case "$tag" in
			v*) ;;
			*) die "tag '$tag' does not start with v (want v1.2.3, or v1.2.3-rc.1)" ;;
		esac
		local v="${tag#v}"
		echo "$v" | grep -Eq "$SEMVER_RE" \
			|| die "tag '$tag' is not v<semver> (want v1.2.3, or v1.2.3-rc.1)"
		echo "$v"
		return
	fi

	# Only the two channels below count commits, and only they need history. A
	# shallow clone counts wrong without ever failing, which would hand itch.io
	# a version that silently goes backwards; release.yml checks out with
	# fetch-depth: 0 for exactly that reason, so say so if it ever stops.
	if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
		die "shallow clone — the commit distance would be wrong (need fetch-depth: 0)"
	fi

	local base distance
	local anchor; anchor="$(nearest_release_tag)"
	if [ -n "$anchor" ]; then
		local anchor_version="${anchor#v}"
		echo "$anchor_version" | grep -Eq "$SEMVER_RE" \
			|| die "nearest release tag '$anchor' is not v<semver>"
		base="$(next_version "$anchor_version")"
		distance="$(git rev-list --count "${anchor}..HEAD")"
	else
		base="$BASE_WHEN_UNTAGGED"
		distance="$(git rev-list --count HEAD)"
	fi

	local sha; sha="$(git rev-parse --short=7 HEAD)"
	local v="${base}-${channel}.${distance}+g${sha}"
	# Belt and braces: the shape above is only SemVer if every piece is, and a
	# bad BASE_WHEN_UNTAGGED or an exotic channel name would slip through above.
	echo "$v" | grep -Eq "$SEMVER_RE" || die "produced '$v', which is not SemVer"
	echo "$v"
}

# --- self-test ------------------------------------------------------------
#
# A throwaway repo in a temp dir, because every branch above is a question
# about git history and there is no way to ask it without one. Runs in about a
# second; .github/workflows/tests.yml runs it on every pull request.

self_test() {
	local fails=0
	local dir; dir="$(mktemp -d)"
	# Expanded now, not when the trap runs: `dir` is a local and is gone by
	# then, and under `set -u` that turns the cleanup into an error.
	trap "rm -rf '$dir'" EXIT

	expect() { # expect <what> <got> <want>
		if [ "$2" = "$3" ]; then
			echo "ok   $1: $2"
		else
			echo "FAIL $1: got '$2', want '$3'" >&2
			fails=$((fails + 1))
		fi
	}
	expect_fail() { # expect_fail <what> <channel> [tag]
		local out
		if out="$(version_for "$2" "${3:-}" 2>&1)"; then
			echo "FAIL $1: expected a failure, got '$out'" >&2
			fails=$((fails + 1))
		else
			echo "ok   $1: refused"
		fi
	}
	commit() { git -C "$dir" commit -q --allow-empty -m "$1"; }
	sha() { git -C "$dir" rev-parse --short=7 HEAD; }

	git init -q "$dir"
	git -C "$dir" config user.email t@example.com
	git -C "$dir" config user.name  t
	git -C "$dir" config commit.gpgsign false
	cd "$dir" || die "cannot enter $dir"

	# Untagged history: named for the version it is working toward, not bumped.
	commit one
	commit two
	expect "untagged dev"      "$(version_for dev)"      "0.1.0-dev.2+g$(sha)"
	expect "untagged playtest" "$(version_for playtest)" "0.1.0-playtest.2+g$(sha)"

	# A release tag is the tag, minus the v, and nothing else.
	git -C "$dir" tag v0.1.0
	expect "release"           "$(version_for release v0.1.0)"     "0.1.0"
	expect "release, 2 fields" "$(version_for release v1.2.3)"     "1.2.3"
	expect "release prerel"    "$(version_for release v1.2.3-rc.1)" "1.2.3-rc.1"

	# On the tag itself: distance 0, bumped past the release behind it.
	expect "on the tag, dev"   "$(version_for dev)"      "0.1.1-dev.0+g$(sha)"

	# Past it: the patch bump plus a distance that only goes up.
	commit three
	expect "one past"          "$(version_for dev)"      "0.1.1-dev.1+g$(sha)"
	commit four
	expect "two past"          "$(version_for dev)"      "0.1.1-dev.2+g$(sha)"
	expect "two past playtest" "$(version_for playtest)" "0.1.1-playtest.2+g$(sha)"

	# A test* tag is not a version anchor — the count keeps running past it.
	git -C "$dir" tag test-2026-09-11
	commit five
	expect "test tag ignored"  "$(version_for dev)"      "0.1.1-dev.3+g$(sha)"

	# A pre-release anchor heads toward its own release; nothing is bumped.
	git -C "$dir" tag v0.3.0-rc.1
	commit six
	expect "prerelease anchor" "$(version_for dev)"      "0.3.0-dev.1+g$(sha)"

	# And the newest v* tag wins, not the first one reachable.
	git -C "$dir" tag v0.3.0
	commit seven
	expect "newest anchor"     "$(version_for dev)"      "0.3.1-dev.1+g$(sha)"

	# The bump rule is what makes the ordering come out right, so assert it
	# directly. (Not with `sort -V`: GNU version sort is not SemVer precedence
	# -- it sorts 0.2.2 BEFORE 0.2.2-dev.7 -- so it cannot judge this.)
	expect "bumps the patch"      "$(next_version 0.2.1)"      "0.2.2"
	expect "bumps into a decade"  "$(next_version 1.9.9)"      "1.9.10"
	expect "prerelease not bumped" "$(next_version 0.3.0-rc.1)" "0.3.0"

	# The refusals. Each of these used to be a build published under a version
	# nothing could compare.
	expect_fail "release without a tag" release
	expect_fail "v-less tag"            release 0.1.0
	expect_fail "three-part-less tag"   release v0.1
	expect_fail "date tag as release"   release v2026-09-11
	expect_fail "leading-zero tag"      release v01.2.3

	cd / || true
	if [ "$fails" -ne 0 ]; then
		echo "build_version self-test: $fails failed" >&2
		return 1
	fi
	echo "build_version self-test: all passed"
}

# --- arguments ------------------------------------------------------------

case "${1:-}" in
	--self-test)   self_test; exit $? ;;
	-h|--help|"")  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	release)       version_for release "${2:-${GITHUB_REF_NAME:-}}" ;;
	playtest|dev)  version_for "$1" ;;
	*)             die "unknown channel '$1' (want release, playtest or dev)" ;;
esac
