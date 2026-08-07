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

## When the scan misbehaves: observe, diagnose, adapt

Read the `vyql-run` verdict line first. `killed at Ns cap` (exit 124) is a
timeout; anything else means vyql returned and the problem is in its output.

A true timeout is the exception, not the norm: modern vyql tamed the scope-width
pathology that used to hang it, and even a 94 MB tree of 3400 files finishes in
about two minutes. So when a scan does hit the cap, something specific is wrong -
find it, do not just raise the cap.

### Timeout / stuck (verdict `killed at Ns cap`, exit 124)

A timeout is not automatically a pathology. First tell apart a scan that was
**making progress** from one that was **stuck**, because the fix is opposite.

**Was it just slow? Raise the cap first.** The scope probe sizes the cap from the
file count, and that is only an estimate: a large but healthy tree can genuinely
need longer. The 94 MB tree in `fixtures/stress/SIGNATURES.md` finished at 121s,
so a 120s cap would have killed a perfectly good scan. If the probe found no
giant single file and no blowup hub, and the killed run's output showed findings
accumulating, the timeout means the estimate was low, not that the code is
pathological. Raise the cap a tier and retry, up to the 10-minute hard cap. That
is a real adaptation, not a wasted retry - and it is the right first move here,
not a last resort.

**Was it stuck? A longer cap will not save it.** If the scope probe flagged one
enormous file, or `-stats` shows a hub with high `in` and high `out`, more time
only buys more thrash. Find where the cost is and cut it out. Ask vyql:

```
[stats] files 2 | nodes 70098 | edges 88077 | sources 6000 | sinks 9
[stats] taint hubs (FLOWS in-degree ≥ 8 — shared callees, blowup risk):
  in=3000 out=1   code.Param                 hub.js:7
  in=3000 out=2   code.Param                 hub.js:2
```

A hub with high `in` and high `out` is the combinatorial risk, and its location
names the file to act on. The worst input is machine-generated code (one enormous
function per template, thousands of nested branches). Adapt:

1. `-exclude` the implicated path: the generated, vendored, or outlier file the
   hub or the probe pointed at. Then **report it as unscanned**, naming the file.
   That is honest coverage, not a clean bill. (Recent vyql skips machine-generated
   files by default and reports the count under `-coverage`; the `-include-generated`
   flag puts them back. If your build does that, the file is already handled - just
   confirm it on the coverage line.)
2. `-cache off` - if the on-disk cache is implicated, this can change the load.
3. `-rules vyql/packs/injection` (one pack at a time) - fewer concurrent taint
   hubs, less work per pass.
4. Chunk by directory and scan the parts, letting `-cache` carry state between
   chunks (helps when the cost is spread across files, not one giant file).
5. Still stuck: escalate, and report the file to vyql as a scope-width case. It
   is a vyql issue, not the user's code.

The two branches are not exclusive: raise the cap once for a slow-but-progressing
scan, and if the longer run still dies at the cap, treat it as stuck and work the
list above. Either way the max-3 adaptation budget still bounds the loop.

### Empty or garbage output

1. Cross-check the format: `-format json` vs the default text - a rendering bug
   looks different from an analysis one.
2. Narrow with `-rules` to isolate which pack misbehaves.
3. `vyql version` and re-read coverage: an implausibly short scan that read
   almost nothing is the headline, per the honesty rules.
4. Reproducible garbage on a minimal input is a vyql bug: escalate with the
   captured output.
