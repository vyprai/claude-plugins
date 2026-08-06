---
name: vyql-security-scan
description: >-
  Scan a codebase for security vulnerabilities with VyQL and triage what it
  finds, following tainted data from source to sink and naming the neutralizing
  controls that are missing. Use when asked to find vulnerabilities, run a
  security scan or audit, review a diff or pull request for security problems,
  check for injection, XSS, SSRF, path traversal or hardcoded secrets, review
  code for security issues, or judge whether a specific scanner finding is real
  or a false positive. Covers Java, Python, JavaScript/TypeScript, Go, C#, PHP,
  Ruby and 15 more languages.
license: Apache-2.0
compatibility: >-
  Requires the vyql CLI (v0.2.0+). Offers to download a release archive on first
  use if absent, with the user's confirmation. Network access is needed only for
  that install.
metadata:
  author: vyprai
  repository: https://github.com/vyprai/vyql
---

# VyQL security scan

VyQL follows tainted data from where it enters a program to where it does
something dangerous, and reports **the neutralizing controls it looked for and
did not find**. That last part is what makes triage possible: a finding is not
"this looks risky", it is "this value reaches this sink and none of these
specific controls is on the path."

## Before anything: is vyql installed?

```sh
vyql version
```

If that fails, read `references/install.md` and **ask before installing
anything**. Never download and run a binary on someone's machine unannounced.

## The flow

One path, five phases. Run them in order.

```
scope → scan → coverage → list → verify → reproduce
```

Most requests start at scope. If the user arrives holding a finding already,
theirs or another scanner's, skip to **verify**. If they ask "why did this not
fire", read `references/debugging.md` instead.

Stop after any phase the user did not ask to go past. A list of findings is a
complete answer to "what is wrong here"; do not verify all of them uninvited,
and do not write a reproduction unless asked.

---

## 1. Scope

Decide what to look at before running anything.

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

## 2. Scan

```sh
vyql scan -fail-on none -all .
```

`-fail-on none` matters. By default `scan` exits 1 when it finds anything HIGH
or CRITICAL, which is right for CI and wrong here. A non-zero exit reads as "the
scan failed" and derails the run. `-all` adds attention and review flags that a
plain scan omits.

A plain scan already reports every severity; the gate only changes the exit
code. There is no flag to "show more findings".

## 3. Coverage, before any finding

The output ends with what was read, and warns about what was not:

```
scanned python:1 textpattern:1 — 9 finding(s)
warning: 15 file(s) matched no frontend and were not analysed (.zig 12, .cob 3)
```

**Never suppress that warning, and never list findings without it.** A clean
report over a tree that was mostly skipped looks exactly like a clean report over
a tree that was fully read. Run `vyql scan -coverage .` for the full account when
anything looks off.

Three things to state plainly, before any finding:

1. **What was actually parsed**, from the `scanned` line, against what is in the
   repository. If it says `python:1` and the project is forty Java files, that is
   the headline, not the findings.
2. **Depth.** Java, Python and JavaScript are the reference frontends. Other
   languages range down to call-and-concat coverage, so "no findings" in Elixir
   means materially less than in Java.
3. **Never say "no vulnerabilities".** Say "no findings in what was analysed",
   and say what that was.

One gap the tool admits and you should repeat when it matters: a file whose parse
partially failed still counts as parsed, because tree-sitter recovers from syntax
errors.

## 4. List

Report all of them. There is no cap, and summarising some away loses the ones the
user most needs.

1. Number the findings, so the user can say "2 is wrong" without quoting it back.
2. Give every finding a `path:line`.
3. Lead with the rule and severity, then one line on what reaches what.
4. Keep it short. This phase is the menu, not the analysis.

Order by severity, then by how much of the code the finding sits in front of.

Then ask which to verify. Offer "all HIGH and CRITICAL" as the default, because
that is the useful batch and it is bounded.

**On verifying everything:** a serial verify of two hundred findings will run out
of room and start degrading silently, which is worse than not doing it. Verify
all HIGH and CRITICAL, then say plainly what was left and offer the next batch.

## 5. Verify

VyQL is a static analyzer. Verification here means the path holds up under
scrutiny, not that the bug is exploitable. Say it in those terms and never report
a verified finding as proof of exploitability.

### First: where does this code live?

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

### Then: read what fired

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

### Then: three questions, in this order

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

### Say what would change your mind

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

## 6. Reproduce

Only when asked, and only for a finding that survived verify.

A reproduction is **a failing test or a local request that shows the path is
real**. It is not an exploit, and its job is to let the developer confirm the bug
now and prove the fix later.

Three rules, and they are not negotiable.

- **Ask first.** Say what you are about to write and where it runs.
- **Local only.** Against a service the user started on their own machine, or as
  a test in their own suite. Never point it at a deployed host, a staging
  environment, or any address the user has not confirmed is theirs.
- **Do not run it against anything you did not just create.** Writing the repro
  is the deliverable. Executing it is the user's call.

Prefer the form the repo already has. A project with tests gets a failing test:

```python
def test_download_rejects_traversal(client):
    r = client.get("/download", query_string={"name": "../../etc/passwd"})
    assert r.status_code == 400        # fails today, passes once fixed
```

A service without a suite gets the request shape instead, against localhost.

**What it proves:** the path is reachable with the input the analyzer claimed.
Not the blast radius, not that it is exploitable in production, and not that
other paths to the same sink are safe.

If the finding is a missing control rather than a reachable path, a hardcoded
secret or weak cipher, there is nothing to reproduce. Say so instead of inventing
a test.

## Record the verdict, or it is lost

Triage that lives only in the conversation is gone the moment it ends, and the
next scan reports all of it again. Offer to write the verdicts down:

```sh
vyql scan -baseline .vyql-baseline.json .     # report only what is new
```

Entries are keyed on the finding fingerprint, anchored to rule and location
rather than line number, so a verdict survives edits elsewhere in the file.

```json
{ "fp": "cfb54bfb4024aa90", "verdict": "false-positive",
  "reason": "source is a build-time constant, not request data" }
```

`false-positive` and `accepted` are different claims. One says the finding is
wrong, the other says it is right and being lived with. Record which, and always
write the reason: an entry with no reason is a suppression nobody can review.

For a codebase with an existing backlog, `-baseline-write .vyql-baseline.json`
records everything as `accepted` so the gate fires only on new findings. Say
plainly that this accepts the backlog rather than fixing it.

**If the scan warns that baseline entries match nothing, surface it.** The code
they excused has changed, and a suppression that outlives its reason is worse
than no suppression.

## Proposing a fix

Name the control from the `unless` clause, give the idiom for the language, say
where it goes. **Do not edit the code.** The user applies it.

If they do apply a fix, re-scanning is a reasonable check, but say what it
proves. A green re-scan means the pattern stopped matching. It does not mean the
code is safe, and reporting it as proof would be the same overclaim this tool
exists to avoid.

## Honesty rules

These are the difference between a useful security report and a dangerous one.

- Coverage before findings, every time.
- "No findings in what was analysed", never "no vulnerabilities".
- A false positive is a finding about VyQL, not a nuisance. Report the binding
  gap.
- Do not raise confidence beyond what the evidence supports. `conf=medium` with
  an unverified source is a lead, not a vulnerability.
- Verified means the static path holds up. It does not mean exploitable.
- If a scan took an implausibly short time or read implausibly few files, say so
  before anything else.

## Command reference

| Command | Answers |
|---|---|
| `vyql scan -fail-on none -all .` | what is wrong, everything reported |
| `vyql scan -coverage .` | what was read, skipped, and left unanalysed |
| `vyql scan --format json .` | findings as JSON, for `diff` |
| `vyql diff before.json after.json` | what a change introduced or removed |
| `vyql explain .` | why each finding fired, with negation evidence |
| `vyql query -concept X .` | every node labelled with a concept |
| `vyql trace -from X -to Y .` | the path, or where it stops |
| `vyql match .` | what got labelled at all |
| `vyql resolve .` | which calls did not resolve |
| `vyql definitions -kind concepts` | the concept vocabulary |

`-from`, `-to` and `-concept` are substring filters over concept names. A filter
matching no known concept is an error with a suggestion, not an empty result. If
you get one, fix the name rather than concluding there is nothing there.

Paths work as they do for `scan`; with no path, the working directory is used.
