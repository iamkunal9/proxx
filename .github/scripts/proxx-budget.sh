#!/usr/bin/env bash
# proxx: fail this job when it ran longer than its budget (docs/proxx/ci.md).
# Usage: proxx-budget.sh "<job name as shown in the run>" <budget seconds>
# Measures from the job's start on the runner (setup included) to now.
set -euo pipefail
name="$1"
budget="$2"
started="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs" \
	--paginate --jq ".jobs[] | select(.name == \"$name\") | .started_at" | head -1)"
if [ -z "$started" ]; then
	echo "::error::budget: job \"$name\" not found in this run"
	exit 1
fi
took=$(($(date +%s) - $(date -d "$started" +%s)))
line="budget: $name took ${took}s (budget ${budget}s)"
echo "$line" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [ "$took" -gt "$budget" ]; then
	echo "::error::$line"
	exit 1
fi
