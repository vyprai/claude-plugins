# Choosing what to scan

Read this when working through phase 1 of `SKILL.md`.

| The user is asking | Scope |
|---|---|
| "audit this repo", "is this codebase secure" | the whole tree |
| "review this PR", "did my change introduce anything" | the diff |

**The change-based case is different and matters.** "Is this branch secure?",
"find the vulnerabilities in this PR", "did my change introduce anything" all
ask for what the change *added*, not the repo's whole backlog. On a codebase
with a backlog, a whole-tree scan buries the two findings the change introduced
under two hundred it did not.

Record the base's findings as an accepted baseline, then report only what is new
against it. `-baseline-write` writes the base's findings as accepted;
`-baseline` excludes them from the next scan, so what remains is the change:

```sh
base=$(git merge-base HEAD origin/main)          # or the PR's base ref
git worktree add -q /tmp/vyql-base "$base"
# Record every finding that already exists on the base as accepted.
sh references/vyql-run.sh <cap> /tmp/bw.out -- \
  vyql scan -fail-on none -flags with -baseline-write /tmp/base.json /tmp/vyql-base
# Report only the findings the change introduced.
sh references/vyql-run.sh <cap> /tmp/new.out -- \
  vyql scan -fail-on none -flags with -baseline /tmp/base.json .
git worktree remove /tmp/vyql-base --force
```

Use the **same flags on both sides** (`-flags with` here), or findings that only one
side reports all read as new.

**Use a worktree, never `git stash`.** Stashing puts the user's uncommitted work
somewhere they did not ask for it, and if anything fails between the stash and
the pop it stays there silently. A worktree is a separate checkout: the working
tree is untouched whatever happens, and a leftover one is harmless.

The baseline keys on the finding fingerprint, anchored to rule and location
rather than line number, so moving a function does not read as new. Report the
new findings; mention resolved ones only if the user is checking a fix.
`vyql diff before.json after.json` over two `-format json` scans is an
equivalent alternative when you want both the added and the removed lists.

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

## Offer a skip list, then confirm

Before the first scan, propose a skip list tuned to the project, and **wait for
the user to approve it**. A directory skipped here is a directory the report will
call clean without having read it, so this is the one gate before the scan.

Two facts keep the proposal honest:

**What vyql already skips, so do not propose it.** The walk drops
`node_modules`, `.git`, `dist`, `target`, `__pycache__`, `.venv`, `venv`,
`testdata`, `vendor`, and `build` when it sits at the scan root — plus every
dot-directory except `.github`, `.circleci` and `.buildkite`, which are scanned
because CI configuration is worth reading. The Go frontend also skips `*_test.go`.

So for a Go project, test files and vendored dependencies are *already* gone:
saying "I will skip `*_test.go`" is wrong, and so is offering `.venv` on a Python
project or `target` on a Java one. Check this list before offering anything.

**`-exclude` takes one pattern per flag, and is repeatable.** One rule decides
what a pattern means:

| Pattern | Matches |
|---|---|
| `migrations` | that directory, at any depth |
| `'**/*_test.go'` | that file, at any depth |
| `'src/gen/**'` | rooted at the scan root, because it has a slash |
| `'**/*.{spec,test}.ts'` | brace alternation |

A bare name is a directory; anything with a glob character or a slash is matched
against the path. Repeat the flag for more than one pattern — a comma is rejected,
because it would be ambiguous with a valid glob:

```sh
vyql scan -exclude vendor -exclude '**/*_templ.go' .
```

Directory patterns are the cheap ones: an excluded directory is never descended,
so nothing under it is read. A file glob still has to see the filename to reject
it. Prefer a directory name when either would do.

Detect the project from its manifests (`go.mod`, `package.json`,
`requirements.txt`/`pyproject.toml`, `pom.xml`) and offer the segments that are
*not* already default and that are unlikely to hold real findings:

| Project | Worth offering (beyond the defaults) |
|---|---|
| Go | `third_party`, `mocks`, `'**/*_templ.go'`, `'**/*.pb.go'` |
| Python | `migrations`, `tests` |
| JS / TS | `coverage`, `out`, `__mocks__`, `'**/*.min.js'` |
| Java / Kotlin | `generated-sources`, `'**/*Generated.java'` |
| any | `fixtures`, `examples`, `docs` |

Nothing in that table is skipped by default. `.venv`, `venv`, `target`,
`__pycache__` and `.next` are, so offering them wastes the user's attention on a
choice already made.

Skipping a test directory is a judgment call, not a default: security bugs do
live in test helpers, and a finding in `testdata/` is usually not a vulnerability
(see `references/triage.md`). So **offer, name what you would add, and wait for
the user to confirm** before scanning with the enlarged skip list. If they
decline, scan with the defaults.
