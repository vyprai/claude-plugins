# Scanning, bounded and resilient

Read this when working through phase 2 of `SKILL.md`, or whenever a vyql
invocation hangs or returns something you do not trust.

## Every vyql call is time-bounded

vyql can get stuck: on a single very large file (tens of thousands of LOC) its
CGO/Badger internals thrash, and because that memory lives outside the Go
runtime it does not crash, it just stops progressing. Managing that memory is
vyql's job, not the skill's. The skill's job is only to guarantee no call hangs,
with a wall-clock cap. Stock macOS has no `timeout`, so use this time-boxer. It
kills the command at the cap and always leaves its output on disk for the
observe step.

```sh vyql-run
#!/bin/sh
# Time-box one command, portably (stock macOS has no `timeout`).
#   vyql-run.sh <cap_seconds> <out_file> -- <cmd> <args...>
# Exit: the command's own code if it finished; 124 if the cap fired. Always
# leaves the command's stdout+stderr in <out_file>.
set -u
cap=$1; out=$2; shift 2
[ "${1:-}" = "--" ] && shift
: > "$out"
flag="$(mktemp)"
"$@" >"$out" 2>&1 &
pid=$!
# Timer: mark the flag, then kill, so the flag is set before the wait unblocks.
( sleep "$cap"; echo hit > "$flag"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) &
timer=$!
wait "$pid" 2>/dev/null; rc=$?
kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null
if [ -s "$flag" ]; then
  rm -f "$flag"; echo "vyql-run: killed at ${cap}s cap" >&2; exit 124
fi
rm -f "$flag"; echo "vyql-run: exited rc=$rc within ${cap}s cap" >&2; exit "$rc"
```

The cap comes from the scope probe (`references/scope.md`): a size tier of
2, 5, or 10 minutes. Do not pass `-max-ram` or otherwise try to bound memory -
that is vyql's own knob and its own concern. Bound time, observe the result:

```sh
sh references/vyql-run.sh 300 /tmp/vyql.out -- vyql scan -fail-on none -all .
```
