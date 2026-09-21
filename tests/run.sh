#!/usr/bin/env bash
# Runs every regression suite in tests/ and fails if any check fails.
#
#   ./tests/run.sh              headless (CI-friendly; skips the 2 checks that
#                               need a real input path: Input.parse_input_event)
#   ./tests/run.sh --windowed   runs windowed too, which is the full 104 checks
#   GODOT=/path/to/Godot ./tests/run.sh
#
# Each suite is a scene (not a script): the gameplay ability plugin uses its
# autoload singletons as global identifiers, which only resolve in a normal
# project run (AGENTS.md pitfall 12). Suites exit non-zero when a check fails.
set -uo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# GODOT may be set explicitly (CI does); otherwise look for an installed build.
if [ -z "${GODOT:-}" ]; then
	if [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
		GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	else
		GODOT="$(command -v godot || true)"
	fi
fi
WINDOWED=0
[ "${1:-}" = "--windowed" ] && WINDOWED=1

if [ ! -x "$GODOT" ]; then
	echo "Godot not found at: $GODOT" >&2
	echo "Set it explicitly, e.g.: GODOT=/path/to/Godot $0" >&2
	exit 2
fi

# The whole point of these suites is the *count* of passing checks, so collect
# them and compare with the expected totals; a suite that silently stops early
# (exit 0 with fewer checks) must not pass unnoticed.
declare -a SUITES=(
	"verify_match:35:35"
	"verify_indicator:28:30"
	"verify_feedback:19:19"
	"verify_grenade:17:17"
	"verify_3v3:24:24"
)

failures=0
total_passed=0
total_expected=0

run_suite() {
	local name="$1" headless_passed="$2" windowed_passed="$3"
	local mode="--headless"
	local expected="$headless_passed"
	if [ "$WINDOWED" = "1" ]; then
		mode="--windowed"
		expected="$windowed_passed"
	fi

	local output
	if [ "$mode" = "--headless" ]; then
		output="$("$GODOT" --headless --path "$PROJ" --fixed-fps 60 "res://tests/$name.tscn" 2>&1)"
	else
		output="$("$GODOT" --path "$PROJ" --fixed-fps 60 "res://tests/$name.tscn" 2>&1)"
	fi
	local status=$?

	local summary passed
	summary="$(printf '%s\n' "$output" | grep -E '^=== ' | tail -1)"
	passed="$(printf '%s\n' "$output" | grep -cE '^PASS ')"
	local failed skips
	failed="$(printf '%s\n' "$output" | grep -cE '^FAIL ')"
	skips="$(printf '%s\n' "$output" | grep -cE '^SKIP ')"

	# Script errors are failures even if the checks happened to pass.
	if printf '%s\n' "$output" | grep -qE 'SCRIPT ERROR|Parse Error'; then
		failed=$((failed + 1))
		printf '%s\n' "$output" | grep -E 'SCRIPT ERROR|Parse Error' | head -3 | sed 's/^/    /'
	fi

	total_passed=$((total_passed + passed))
	total_expected=$((total_expected + expected))

	# --headless drops the display driver, which is what makes the engine-input checks
	# skip; --windowed simply runs without it.
	if [ "$status" -ne 0 ] || [ "$failed" -ne 0 ] || [ "$passed" -lt "$expected" ]; then
		failures=$((failures + 1))
		printf 'FAIL  %-18s %s (passed %d/%d, expected %d, exit %d)\n' \
			"$name" "${summary:-<no summary>}" "$passed" "$((passed + failed))" "$expected" "$status"
	else
		printf 'ok    %-18s %s\n' "$name" "${summary:-$passed checks}"
	fi
	[ "$skips" -gt 0 ] && printf '      %d skipped (needs a real display driver; run with --windowed)\n' "$skips"
}

printf 'running %d suites from %s\n' "${#SUITES[@]}" "$PROJ"
for entry in "${SUITES[@]}"; do
	IFS=: read -r name headless_passed windowed_passed <<<"$entry"
	run_suite "$name" "$headless_passed" "$windowed_passed"
done

printf '\n%d/%d checks passed across %d suites\n' "$total_passed" "$total_expected" "${#SUITES[@]}"
if [ "$WINDOWED" = "0" ]; then
	printf '(headless skips the 2 engine-input checks of verify_indicator; use --windowed for the full run)\n'
fi

if [ "$failures" -ne 0 ]; then
	printf '%d suite(s) failed\n' "$failures"
	exit 1
fi
printf 'all suites passed\n'
