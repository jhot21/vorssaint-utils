#!/usr/bin/env bash
# Fetches vorssaintapp/vorssaint-utils and merges its main branch into a new
# sync branch off of origin/main. Exits 0 on a clean merge (branch is ready
# to open a normal PR from, unless has_changes=false — nothing to sync),
# exits 1 if there were conflicts (branch is left with conflict markers,
# staged for manual resolution).
set -euo pipefail

UPSTREAM_URL="https://github.com/vorssaintapp/vorssaint-utils.git"
UPSTREAM_BRANCH="main"
BASE_BRANCH="main"
DATE_TAG="$(date +%Y-%m-%d)"
SYNC_BRANCH="sync-upstream-${DATE_TAG}"

git fetch origin "${BASE_BRANCH}"
git fetch "${UPSTREAM_URL}" "${UPSTREAM_BRANCH}"

git checkout -B "${SYNC_BRANCH}" "origin/${BASE_BRANCH}"

set +e
git merge --no-ff FETCH_HEAD -m "Sync with upstream vorssaintapp/vorssaint-utils@${UPSTREAM_BRANCH} (${DATE_TAG})"
MERGE_STATUS=$?
set -e

if [ "${MERGE_STATUS}" -ne 0 ]; then
  git add -A
  git commit -m "WIP: conflicted sync with upstream (${DATE_TAG}) — conflict markers committed for manual resolution"
fi

# Write outputs BEFORE push so they're recorded even if push fails
echo "sync_branch=${SYNC_BRANCH}" >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [ "${MERGE_STATUS}" -ne 0 ]; then
  echo "merge_conflict=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  echo "has_changes=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
else
  echo "merge_conflict=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  # A clean merge with nothing to bring in (upstream already fully present)
  # leaves the sync branch identical to origin/main — no PR should be opened.
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/${BASE_BRANCH}")" ]; then
    echo "has_changes=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  else
    echo "has_changes=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
  fi
fi

# Push happens after outputs are written, so a push failure doesn't hide merge status
git fetch origin "${SYNC_BRANCH}" 2>/dev/null || true
git push origin "${SYNC_BRANCH}" --force-with-lease

# Exit with merge status (0 for clean merge, 1 for conflicts)
exit "${MERGE_STATUS}"
