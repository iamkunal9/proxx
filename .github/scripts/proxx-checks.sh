#!/usr/bin/env bash
# proxx: small CI checks folded into one job. Every check runs; the job lists every failure.
# Usage: proxx-checks.sh [base-ref]   (base-ref enables the PR-only translator path guard)
set -uo pipefail

base="${1:-}"
failures=()
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

# check NAME BUDGET_SECONDS CMD...: a check that passes but takes longer than its budget fails.
check() {
	local name="$1" budget="$2"
	shift 2
	local start out status
	start=$(python3 -c "import time;print(time.time())")
	out="$("$@" 2>&1)"
	status=$?
	local took
	took="$(python3 -c "import time;print(round(time.time()-$start,2))")"
	if [ $status -eq 0 ] && python3 -c "import sys;sys.exit(0 if $took > $budget else 1)"; then
		out="took ${took}s, budget ${budget}s"
		status=1
	fi
	printf '%-28s %5.1fs %s\n' "$name" "$took" "$([ $status -eq 0 ] && echo ok || echo FAIL)"
	if [ $status -ne 0 ]; then
		failures+=("$name")
		printf '%s\n' "$out" | sed 's/^/    /'
	fi
}

gofmt_clean() {
	local files
	files="$(git ls-files -z '*.go' | xargs -0 -P 4 -n 200 gofmt -l)"
	[ -z "$files" ] || {
		echo "gofmt -w these files:"
		echo "$files"
		return 1
	}
}

translator_guard() {
	# Upstream rule (AGENTS.md): PRs must not change internal/translator/ on their own.
	local changed
	changed="$(git diff --name-only "$base"...HEAD -- internal/translator/)"
	[ -z "$changed" ] || {
		echo "Changes under internal/translator are not allowed in pull requests:"
		echo "$changed"
		return 1
	}
}

check gofmt 1 gofmt_clean
check "go vet" 5 go vet ./...
check "go mod tidy" 5 go mod tidy -diff
check "codex catalog valid" 5 go run ./cmd/validate_codex_models --file internal/registry/models/codex_client_models.json
check "test inputs inventory" 5 python3 .github/scripts/proxx_ci.py inventory
if [ -n "$base" ]; then
	check "translator path guard" 1 translator_guard
fi

if [ ${#failures[@]} -ne 0 ]; then
	{
		echo "### checks: ${#failures[@]} failed"
		printf -- '- %s\n' "${failures[@]}"
	} | tee -a "$summary"
	exit 1
fi
echo "### checks: all passed" | tee -a "$summary"
