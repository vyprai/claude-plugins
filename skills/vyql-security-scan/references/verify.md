# Verifying a finding

Read this when working through phase 5 of `SKILL.md`.

## VyQL's finding is a hypothesis

The proof tree is the map, the code is the territory. Every verdict rests on
code you opened and a path you walked by hand, not on what the scanner asserts
about itself - because bindings and taint modelling do not cover every language,
framework, or templating engine, and a confident-looking path can rest on a
mislabelled source. `vyql match`, `vyql resolve` and `vyql trace` corroborate;
they never substitute for reading the code. A verdict that cites only the
scanner is not a verdict.

## Group by CWE, collapse by root cause, then fan out

Group the findings before verifying any of them, and settle the cheap structural
signals before spending a subagent on anything.

```sh
vyql scan -fail-on none -format json . > /tmp/vyql-findings.json
```

Each finding carries a `rule` like `VYQL-INJ-004` and a CWE like `CWE-89`. Group
by **CWE** — that is the axis a reader acts on and a fix lands on — then order the
groups by the highest severity each one contains.

Within a CWE, collapse findings that share a **root cause** into one cluster: the
same rule and sink API, the same taint source `file:line`, or the same
unsatisfiable `unless` line. One cluster gets one verdict, and the verdict names
how many findings it retires.

**Run the structural signals in `references/blindspots.md` against each cluster
first.** They settle a cluster from the scan output plus at most one grep — a CWE
the language cannot express, a name-collision sink, one handle tainting everything,
an orphaned sink, a wrong-surface rule, an existing suppression. This is done in
the main loop, cheaply, and it is what makes a scan of thousands of findings
tractable. Only clusters that survive the structural pass need the source-reading
verification below, and only those are worth a subagent.

Never collapse a cluster without confirming the shape: `blindspots.md` explains
why an orphaned sink is unadjudicated rather than safe, and why a CWE is wrong for
an API shape and not for the language.

### Write the worklist before dispatching

Fan-out state must outlive this conversation, so a different session (or person)
can resume. Before spawning anything, write `vyql-triage.md` at the scanned
repo's root (offer to add it to `.gitignore`), and save the raw scan JSON beside
it:

```sh
vyql scan -fail-on none -format json . > vyql-findings.json
```

`vyql-triage.md` structure:

```markdown
# VyQL triage: <commit sha>, <date>
Coverage: <scanned line>. Binding gaps: <frameworks with no bindings>.
Blindspots: <orphaned sinks, unscanned filetypes, shallow packs>.

## Clusters (by CWE, collapsed by root cause; count each retires)
1. [ ] CWE-502  critical  341  DESER-001, json.Unmarshal into typed struct
2. [ ] CWE-78   critical   13  INJ-002, `.exec` name collision (RegExp.exec)
3. [ ] CWE-502  critical  412  DESER-001, all from one ws.go:8 conn source
4. [ ] CWE-347  high        1  CFG-005, jwt.ParseUnverified

## Structural pass (settle before spending a subagent)
- [x] 1  false-positive: CWE-502 needs type instantiation; Go typed decode cannot
- [x] 2  false-positive: name collision, no child_process import
- [x] 3  false-positive: single handle source, collapse fan-out to one verdict
- [ ] 4  survives structural pass -> source reading

## Deep verify (survivors only, one subagent per cluster, 4 max)
- [ ] CWE-347 (1)  verdict:

## Verdicts (append as they land)
### CWE-347 / CFG-005: real | false-positive | unresolved
counterevidence: ...
proof gaps: ...
```

A later session resumes by re-scanning, `vyql diff vyql-findings.json <new>.json`
to confirm nothing moved, and picking up unchecked boxes. The worklist is working
state; `references/baseline.md` remains the settled-verdict record.

Spawn one subagent per surviving cluster, **at most four per run**. Give each:

- its cluster's findings, as the JSON objects
- the repository path
- the matching CWE section of `references/triage.md`
- `references/blindspots.md`, so it applies the structural signals and the
  false-negative safeguards itself
- this file, from the next section onward

Each returns verdicts in the format below: surface and source trust, the three
questions, counterevidence, proof gaps.

Four is a cost bound. A noisy scan can hold many clusters, and one subagent each
is a token surprise large enough that someone uninstalls the skill over it. The
structural pass already retired the large false-positive clusters cheaply, so four
deep-verify subagents is usually enough for the survivors; four also keeps the
returned verdicts small enough to reconcile in one reply.

Clusters past the cap are **deferred, by name**, with an offer to run the next
batch. Never drop one silently.

If a subagent errors or times out, do not drop its cluster. Work the ladder:

1. Retry once with narrower scope: one finding at a time instead of the whole
   cluster, so one pathological path cannot sink the batch.
2. Still failing: mark the cluster **deferred by name** in `vyql-triage.md` with
   what was tried, and offer to run it alone next.

A silently dropped cluster means a whole class went unexamined with nobody
noticing. That is the one outcome forbidden here.

**Where there is no subagent capability**, run the same procedure sequentially in
the main loop, one cluster at a time, and say that is what is happening. This file
is a plain reference; nothing here needs subagents except the speed.

### Why cluster by root cause and not severity

Triage has already ordered by severity, so severity is spent by the time verify
starts.

The stronger reason is that systematic false positives arrive together, from one
mislabelled binding. A repository with a sanitizer VyQL does not model will not
produce one wrong finding; it produces every path traversal that flows through
that helper. A concept mapped to the wrong CWE for a language does not produce one
wrong finding; it produces every call of that API in the codebase. One agent
holding the whole cluster spots the shared cause in a single pass and writes one
verdict. Split across severity buckets, several agents each conclude "looks real"
and nobody sees the pattern.

VyQL is a static analyzer. Verification here means the path holds up under
scrutiny, not that the bug is exploitable. Say it in those terms and never report
a verified finding as proof of exploitability.

## First: where does this code live?

Ask this before the taint questions. It settles more findings than they do, and
VyQL has no idea whether the code it was pointed at ships.

| Surface | What a finding there usually means |
|---|---|
| hosted service, HTTP handler, RPC endpoint | real, treat it as such |
| library or package API | real, but the caller supplies the input; say so |
| CLI run by the repo's own developer | depends entirely on who runs it |
| test fixture, `testdata/`, example, demo | almost never a vulnerability |
| vendored or generated code | real, but not this repo's fix to make |

And classify the source's trust:

- untrusted remote input
- tenant or user-controlled data
- trusted operator or developer configuration
- **an extension point that is meant to execute code**

That last one matters. A plugin loader that evals, a template engine that
renders, a migration runner that executes SQL: these are doing their job. The
finding is only real if untrusted input reaches the extension point, which is a
different question from whether the sink is dangerous.

State the surface and the source trust in the verdict. "Command injection in a
test fixture" and "command injection in a request handler" are not the same
finding.

## Then: read what fired

```sh
vyql explain .
```

```
[P2] [CRITICAL] VYQL-INJ-002  (conf=high, fp=cfb54bfb4024aa90)
    source: code.HttpInput @ server.js:4
    sink: code.CommandExecution @ server.js:5
    taint path: server.jsAttr#77 -> server.jsFormat#78 -> server.jsArg#80
    unless path coveredBy core.ShellEscape: not satisfied
    unless endpoint coveredBy core.CommandArgumentValidation: not satisfied
```

The `unless` lines are the fix list. Each names the control whose absence made
the finding fire, so the fix is "introduce this control", in the language's
idiom.

`conf=` is the engine's own confidence. Low confidence is a hint to look harder,
not permission to dismiss.

## Then: three questions, in this order

Work all three before answering. Do not stop at the first that resolves: a source
that turns out to be a constant tells you nothing about whether the path was
real, and the next scan will ask again.

**1. Is the source genuinely attacker-controlled?**

```sh
vyql query -concept HttpInput .
```

Lists every node that got the label, with its location. If the "source" is a
constant, a test fixture or an internal caller, the finding is a false positive.
Say so, and show this output as the reason.

**2. Does the path really carry the value?**

```sh
vyql trace -from HttpInput -to SqlExecution .
```

Read the hops in `taint path:`. A path through a function that discards or
replaces the value is a false positive.

**3. Is there a control VyQL did not model?**

If the code neutralizes the value by a route the ontology does not know, you have
found two things: the finding is a false positive, **and** there is a binding
gap. Report both. The second is how coverage improves, and it is worth more than
the first.

Before concluding this, check one known modelling limitation: an inline control
call inside a concatenation sometimes fails to neutralize where assign-then-use
works.

```python
sink("... " + escape(p))     # may not register as covered
clean = escape(p)            # does
sink("... " + clean)
```

If that is the shape, the code is fine and the finding is a modelling gap, not a
vulnerability.

Per-family judgment, what makes an injection, path traversal, SSRF, crypto or
secret finding real, is in `references/triage.md`.

## Say what would change your mind

Every verdict carries two things beyond the answer.

**Counterevidence:** what you found that argues the other way. A guard one call
up, a caller that only ever passes constants, a deploy config that never enables
the route. Include it even when you still think the finding is real. A verdict
with nothing against it usually means nobody looked.

**Proof gaps:** what you could not establish from the code. Whether the route is
registered in production, whether the config toggle defaults on, whether the
caller is internal. Name them rather than assuming the safe answer or the scary
one.

A finding you cannot settle is a legitimate outcome. Report it as unresolved,
name the gap, and say the smallest thing that would close it.

## A false-positive verdict must disprove the finding, not just fail to prove it

"False positive" and "unresolved" are different verdicts, and collapsing them is
how a real vulnerability gets filed as noise. A false-positive verdict has to name
the thing that makes the code safe:

- the control that neutralizes the path — the sanitizer, the parameterization, the
  canonicalization-then-check;
- or why the CWE cannot apply to this API shape — the typed decode target, the RE2
  engine, the constant source;
- or why the sink is not the dangerous API — the name collision, the ORM struct
  argument.

"I read the code and could not find where this is exploitable" is **not** a
false-positive verdict. It is unresolved, and it is exactly the shape an orphaned
sink produces — VyQL could not clear the class, and neither could you. Report it as
unresolved with the gap named. Only disproving evidence downgrades a finding to
false positive.

