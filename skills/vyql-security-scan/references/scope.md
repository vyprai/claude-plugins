# Choosing what to scan

Read this when working through phase 1 of `SKILL.md`.

| The user is asking | Scope |
|---|---|
| "audit this repo", "is this codebase secure" | the whole tree |
| "review this PR", "did my change introduce anything" | the diff |

**The diff case is different and matters.** On a codebase with an existing
backlog, scanning the whole tree at review time buries the two findings the
change actually introduced under two hundred it did not. Scan both sides and
diff:

```sh
base=$(git merge-base HEAD origin/main)          # or the PR's base ref
git worktree add -q /tmp/vyql-base "$base"
vyql scan -fail-on none --format json /tmp/vyql-base > /tmp/before.json
vyql scan -fail-on none --format json .           > /tmp/after.json
vyql diff /tmp/before.json /tmp/after.json
git worktree remove /tmp/vyql-base --force
```

**Use a worktree, never `git stash`.** Stashing puts the user's uncommitted work
somewhere they did not ask for it, and if anything fails between the stash and
the pop it stays there silently. A worktree is a separate checkout: the working
tree is untouched whatever happens, and a leftover one is harmless.

`diff` keys on the finding fingerprint, which is anchored to rule and location
rather than line number, so moving a function does not read as new findings.
Report the added ones. Mention removed ones only if the user is checking a fix.

## Probe the tree first

Before the first scan, size the tree so the time bound fits it. This probe is
itself bounded: it reads file sizes, and counts lines only on the few largest.
It does not probe memory - that is vyql's concern.

```sh
# Tree size, and the ten largest files by bytes (cheap), then LOC on those only.
files=$(git ls-files | wc -l | tr -d ' ')
git ls-files -z | xargs -0 wc -c 2>/dev/null | sort -rn | sed -n '2,11p' \
  | awk '{print $2}' | tr '\n' '\0' | xargs -0 wc -l 2>/dev/null
```

**Pick the wall-clock cap from the file count:**

| Files tracked | Cap |
|---|---|
| under 2,000 | 120s |
| 2,000 to 20,000 | 300s |
| over 20,000 | 600s (hard cap) |

A 94 MB tree of ~3,400 files scans in about 120s, well inside the 300s tier, so
these tiers leave real headroom rather than cutting a healthy scan short.

**Pre-adaptations (they do not count against the retry budget):**

- Any file over ~10,000 LOC is a corner case worth noting now, so that if the
  first time-bounded scan hits the cap you already know which file to `-exclude`,
  and you can say up front it may be unscannable.
- Vendored and generated directories (`node_modules`, `_vendor`, `dist`, `build`,
  generated protobuf) go straight into `-exclude`. Recent vyql already skips
  machine-generated files on its own, but excluding a known vendored tree up
  front is still cheaper than reading it.

Carry the cap and the exclude list into every `vyql-run` invocation for the rest
of the run.
