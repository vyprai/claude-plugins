---
name: vyql-security-scan
description: >-
  VyQL is a multi-language taint scanner: it follows attacker-controlled data
  from source to sink and reports the neutralizing controls that are missing, so
  a finding can be argued with rather than believed. Use when the user names
  VyQL, or asks to find vulnerabilities, run a security scan or audit, review a
  diff or pull request for security problems, check for injection, XSS, SSRF,
  path traversal or hardcoded secrets, or judge whether a scanner finding is real
  or a false positive. Scans resiliently, reports coverage honestly, and verifies
  each finding against the code rather than trusting the scanner. Covers Java,
  Python, JavaScript/TypeScript, Go, C#, PHP, Ruby and 15 more languages.
license: Apache-2.0
compatibility: >-
  Requires the vyql CLI (v0.3.0+). Offers to download a release archive on first
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
scope → scan → coverage → list → verify → reproduce → fix
```

Most requests start at scope. If the user arrives holding a finding already,
theirs or another scanner's, skip to **verify**. If they ask "why did this not
fire", read `references/debugging.md` instead.

Stop after any phase the user did not ask to go past. A list of findings is a
complete answer to "what is wrong here"; do not verify all of them uninvited,
and do not write a reproduction unless asked.

## Where to stop and ask

Confirmation costs attention, so spend it only where a phase costs money or does
something the user cannot undo.

| Phase | Gate |
|---|---|
| scope | **ask.** Propose what to scan and what to skip, wait for a yes |
| scan, coverage | none. Read-only, cheap, and the point of asking |
| list | none to show it. **Ask** before withholding any part of it |
| verify | **ask.** Name the families found, propose the batch, wait |
| reproduce | **ask twice.** Once to write one, again before booting anything |
| fix | **asks, and does nothing until told.** Optional, never reached on its own |

Scope is asked because it decides what the scan cannot find. Everything after it
is read from a scan that already happened, and a user who asked "is this repo
secure" should not be asked three more times whether they meant it.

The list gate runs the other way from the rest. Showing findings needs no
permission; **not** showing them does.

## When you are blocked

A blocked phase is not a finished phase. Say what is blocking you, say what would
unblock it, and wait. If the user supplies it, continue from there rather than
starting again.

Ask once, with the specific thing needed. "The boot failed" is not a question.
"`DATABASE_URL` is unset and postgres did not start. Do you have one I should
use, or shall I write the test instead?" is.

Every ask has a decline path, and declining is not a failure. The fallback still
produces a real artifact.

**A user handing over their own environment is consent.** The rule against
mounting their `.env` is a rule against doing it silently, not against being
given it. But a verdict resting on user-supplied context records that it does:
"real, assuming `internal/` is deployed, which the user confirmed."

## Resilience: never quit at the first error

Every phase can fail, and a failed command is not a finished phase. Work each
failure through one loop, and never retry a command unchanged.

**observe -> diagnose -> adapt -> retry, at most 3 adaptations per phase.**

- **Observe** with vyql's own evidence: exit code, stderr, the `vyql-run`
  verdict line, `-stats`, `-coverage`, wall time.
- **Diagnose** in one written line before retrying. Name the cause, not the
  symptom.
- **Adapt** by changing something material: a flag, the scope, the strategy.
  Retrying a byte-identical command is forbidden. Probe-driven pre-adaptations
  (from scope) do not count against the 3.
- **Retry**, then re-observe.

Each phase's reference file carries its own pivot ladder, because the pivots
differ: scan pivots on flags and scope (`references/scan.md`), reproduce pivots
on boot strategy (`references/reproduce.md`).

**Time-bounded, always.** Run every vyql call, and any other call that can block
(a boot, a long clone), through the `vyql-run` time-boxer in
`references/scan.md`, with a wall-clock cap from the scope probe. Stock macOS has
no `timeout`, which is why the helper exists. The skill does not manage memory:
that is vyql's own concern. The time bound is the single guarantee that no call
hangs.

**Reflect when the ladder runs out.** The references cannot list every failure.
On a symptom none of them names, read `vyql <cmd> -h` and the scope probe and
reason out the next adaptation from the CLI surface. Quitting and repeating are
both failures.

**Escalate after 3.** Report, do not shrug: each command tried, what was
observed, the diagnosis, and 2-3 concrete options the user can choose (scan a
subset, exclude a file, run it overnight, report a vyql bug). A partial scan is
never presented as a complete one.

---

## 1. Scope

Decide what to look at before running anything.

| The user is asking | Scope |
|---|---|
| "audit this repo", "is this codebase secure" | the whole tree |
| "is this branch secure", "review this PR", "what did my change add" | the change |

The change case is not the whole-tree scan with a filter. On a codebase with a
backlog it buries the findings a change introduced under the ones it did not.
Record the base as a `-baseline-write` snapshot and scan with `-baseline` so only
new findings remain. `references/scope.md` has that recipe.

**Ask before you scan, and wait.** Scope decides what the scan cannot find, and
that is not a decision to make on someone's behalf: a directory skipped here is a
directory the report will call clean without having read it.

Propose the tree or the change, and propose a project-tuned skip list alongside
it — the extra directories worth excluding for this stack, and only those vyql
does not already skip. Say why each one is on the list, because "vendored
dependencies you do not patch" and "the code you asked me to audit" are different
things and the user is the one who knows which is which.

```
Scanning the whole tree. vendor/, node_modules/ and testdata/ are skipped
already. On top of those I would skip:

  **/*_templ.go    generated templates, one huge function each
  examples/        sample code, not shipped
  docs/            prose

Anything else to leave out, or shall I go?
```

Naming what is *already* skipped costs a line and buys the user the difference
between "unread because I chose to" and "unread because it always is".

Offer the additions rather than assuming them, and take a "scan everything"
plainly — declining the skip list is a valid answer, not a mistake to argue with.
`references/scope.md` covers what is already skipped by default and how
`-exclude` matches.

## 2. Scan

Run it time-bounded, through the helper, never raw:

```sh
sh references/vyql-run.sh <cap> /tmp/vyql.out -- vyql scan -fail-on none -flags with .
```

`references/scan.md` has the time-boxer, the cap from the probe, and the ladder
for when the scan hangs or returns something you do not trust. Do not pass
`-max-ram`: memory is vyql's concern, the time bound is the skill's.

`-fail-on none` matters. By default `scan` exits 3 when it finds anything HIGH
or CRITICAL, which is right for CI and wrong here. A non-zero exit reads as "the
scan failed" and derails the run. `-flags with` adds attention and review flags
that a plain scan omits.

The four codes are the same on every vyql command, and they tell you which
problem you have:

| code | meaning |
|---|---|
| `0` | the command run successfully |
| `1` | vyql could not complete — bad path, unreadable file, rules that do not compile |
| `2` | the invocation was wrong — unknown flag or command, a value outside its set |
| `3` | the check ran and did not pass — findings at or above `-fail-on` |

`2` is your mistake and the message says what to fix; `1` is a vyql problem and
belongs in an escalation. Never read either as "no findings".

A plain scan already reports every severity; the gate only changes the exit
code. There is no flag to "show more findings".

Diagnostics — `-coverage`, `-stats`, warnings — go to stderr, and only the
report goes to stdout. `vyql-run.sh` captures both into one file, so read it as
written; if you redirect stdout yourself, the coverage account is not in it.

## 3. Coverage, before any finding

The scan ends with what it read and warns about what it did not.

**Never suppress that warning, and never list findings without it.** A clean
report over a tree that was mostly skipped looks exactly like a clean report over
a tree that was fully read.

**Never say "no vulnerabilities".** Say "no findings in what was analysed", and
say what that was.

`references/coverage.md` has what to state and how to read the warning.

## 4. List

Number them, give every one a `path:line`, lead with rule and severity, keep it
short. This phase is the menu, not the analysis. Order by severity.

**Up to about 25 findings, show all of them.** There is no cap worth applying at
that size, and summarising loses the ones the user most needs.

**Past that, show CRITICAL and HIGH, and say exactly what you are holding back.**
A hundred-line list is not a menu; the user scrolls past the thing they needed.
But a shortened list that does not announce itself is the failure this whole
skill exists to avoid — a partial view that reads as a complete one.

So the count and the severities come first, then the shortened list, then the
offer:

```
73 findings: 4 critical, 21 high, 39 medium, 9 low.
Showing the 25 critical and high below. Say the word for the full list,
or for the medium and low on their own.

 1. [CRITICAL] VYQL-INJ-002  api/users.py:88   request body reaches a shell
 …
```

Never drop a severity silently, never say "and others", and never let the
shortened list stand as the answer to "what did you find". The user asked what is
in their code; they are being shown part of it, and they have to know that.

Then ask which to verify, offering "all HIGH and CRITICAL" as the default. A
serial verify of two hundred findings degrades silently, which is worse than not
doing it: verify the batch, then say plainly what was left.

## 5. Verify

VyQL is a static analyzer. Verification here means the path holds up under
scrutiny, not that the bug is exploitable. Say it in those terms and never report
a verified finding as proof of exploitability.

Work in this order, and read `references/verify.md` for how:

1. **Group by rule family** and fan out, one subagent per family, four at most.
   Families past the cap are deferred by name, never dropped.
2. **Where does this code live?** Surface and source trust, before anything else.
   A path traversal in `testdata/` is not a vulnerability, and a plugin loader
   that evals is doing its job.
3. **What fired, and why.** `vyql explain .` gives the proof tree and the
   `unless` lines, which are the fix list.
4. **Three questions**, all of them: is the source really attacker-controlled,
   does the path really carry the value, is there a control VyQL did not model.

Every verdict carries **counterevidence** (what argues the other way, including
when you still think it is real) and **proof gaps** (what the code could not
settle). Unresolved is a legitimate outcome if you name the gap.

## 6. Reproduce

Only when asked, and only for a finding that survived verify.

Boot the application from a clean worktree and exploit that. Never the instance
the developer is already running. If it will not boot, write a failing test
instead and say the boot did not come up, which is the common outcome and not a
degraded one.

Three rules, not negotiable:

- **Ask first**, and say what will be started.
- **Local only.** Never a deployed host, a staging environment, or any address
  the user has not confirmed is theirs.
- **Writing it is the deliverable.** Running it is the user's call.

`references/reproduce.md` has the boot, the exploit and the teardown.

## Record the verdict, or it is lost

Triage that lives only in the conversation is gone the moment it ends, and the
next scan reports all of it again. Offer to write the verdicts into a baseline:
`references/baseline.md`.

## 7. Fix

Optional, last, and never reached on its own.

The default is unchanged: name the control from the `unless` clause, give the
idiom for the language, say where it goes, and leave the edit to the user.

If the user asks for the change to be made, `references/fix.md` has the rules.
Only a finding that survived verify, name the files first and wait, smallest edit
that introduces the control, re-run the reproduction if one exists.

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
- VyQL's report is a hypothesis, not evidence. A verdict cites code you read and
  a path you walked, never only the scanner's claim about itself.
- Silence over an unmodelled framework is not safety. Coverage names the
  frameworks and templating engines in the tree that VyQL has no bindings for.
- A scan that cannot finish within a sane time bound - typically vyql thrashing
  on a very large file - is a vyql-side limitation. Work around it (exclude the
  file, narrow scope) and report it upstream; never present the partial scan as
  complete.

## Command reference

`references/commands.md`.
