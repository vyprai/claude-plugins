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

## Fanning out by family

Group the findings before verifying any of them.

```sh
vyql scan -fail-on none --format json . > /tmp/vyql-findings.json
```

Each finding carries a `rule` like `VYQL-INJ-004`. The family is the middle
segment, `INJ`. Group by it, then order the groups by the highest severity each
one contains.

### Write the worklist before dispatching

Fan-out state must outlive this conversation, so a different session (or person)
can resume. Before spawning anything, write `vyql-triage.md` at the scanned
repo's root (offer to add it to `.gitignore`), and save the raw scan JSON beside
it:

```sh
vyql scan -fail-on none --format json . > vyql-findings.json
```

`vyql-triage.md` structure:

```markdown
# VyQL triage: <commit sha>, <date>
Coverage: <scanned line>. Binding gaps: <frameworks with no bindings>.

## Findings
1. [ ] VYQL-INJ-002  critical  api/users.py:88  request body -> shell
2. [ ] VYQL-PATH-001 high      api/files.py:23  query param -> open()
...

## Batches (one agent per family, 4 max)
- [ ] INJ (2)   verdict:
- [ ] PATH (3)  verdict:
- [ ] CRY (1)   deferred: over the 4-family cap

## Verdicts (append as they land)
### INJ-002: real | false-positive | unresolved
counterevidence: ...
proof gaps: ...
```

A later session resumes by re-scanning, `vyql diff vyql-findings.json <new>.json`
to confirm nothing moved, and picking up unchecked boxes. The worklist is working
state; `references/baseline.md` remains the settled-verdict record.

Spawn one subagent per family, **at most four per run**. Give each:

- its family's findings, as the JSON objects
- the repository path
- the family's section of `references/triage.md`
- this file, from the next section onward

Each returns verdicts in the format below: surface and source trust, the three
questions, counterevidence, proof gaps.

Four is a cost bound. Fourteen families exist in the corpus, and fourteen
subagents is a token surprise large enough that someone uninstalls the skill over
it. Four also keeps the returned verdicts small enough to reconcile in one reply.

Families past the cap are **deferred, by name**, with an offer to run the next
batch. Never drop one silently.

If a subagent errors or times out, do not drop its family. Work the ladder:

1. Retry once with narrower scope: one finding at a time instead of the whole
   family, so one pathological path cannot sink the batch.
2. Still failing: mark the family **deferred by name** in `vyql-triage.md` with
   what was tried, and offer to run it alone next.

A silently dropped family means a whole class went unexamined with nobody
noticing. That is the one outcome forbidden here.

**Where there is no subagent capability**, run the same procedure sequentially in
the main loop, one family at a time, and say that is what is happening. This file
is a plain reference; nothing here needs subagents except the speed.

### Why family and not severity

Triage has already ordered by severity, so severity is spent by the time verify
starts.

The stronger reason is that systematic false positives arrive as a family. A
repository with a sanitizer VyQL does not model will not produce one wrong
finding; it produces every path traversal that flows through that helper. One
agent holding all of them spots the shared call in a single pass. Split across
severity buckets, several agents each conclude "looks real" and nobody sees the
pattern.

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

