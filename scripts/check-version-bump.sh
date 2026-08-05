#!/bin/sh
# Fail when the skill changed but the plugin version did not.
#
#   scripts/check-version-bump.sh <base-ref>
#
# Claude Code uses the plugin version as its update cache key. With an explicit
# `version` in plugin.json, pushing new commits reaches nobody: every installed
# copy sees the same version string and keeps the cached one, and `/plugin
# update` reports "already at the latest version". A skill edit that ships to no
# one is worse than no edit, because the repository says it was fixed.
set -eu

BASE="${1:-origin/main}"
MANIFEST=".claude-plugin/plugin.json"

read_version() {
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

changed="$(git diff --name-only "$BASE"...HEAD -- skills/ || true)"
if [ -z "$changed" ]; then
    echo "skill unchanged; no version bump required"
    exit 0
fi

before="$(git show "$BASE:$MANIFEST" 2>/dev/null | read_version)"
after="$(read_version < "$MANIFEST")"

if [ -z "$after" ]; then
    echo "no version in $MANIFEST" >&2
    exit 1
fi

if [ "$before" = "$after" ]; then
    echo "the skill changed but the version is still $after:" >&2
    printf '%s\n' "$changed" | sed 's/^/  /' >&2
    echo "" >&2
    echo "Bump \"version\" in $MANIFEST, or installed copies keep the cached skill." >&2
    exit 1
fi

echo "skill changed and version moved ${before:-none} -> $after"
