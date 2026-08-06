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

The diff case is not the whole-tree scan with a filter. On a codebase with a
backlog it buries the findings a change introduced under the ones it did not.
`references/scope.md` has the recipe.

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

Work in this order, and read `references/verify.md` for how:

1. **Where does this code live?** Surface and source trust, before anything else.
   A path traversal in `testdata/` is not a vulnerability, and a plugin loader
   that evals is doing its job. This settles more findings than taint analysis.
2. **What fired, and why.** `vyql explain .` gives the proof tree and the
   `unless` lines, which are the fix list.
3. **Three questions**, all of them: is the source really attacker-controlled,
   does the path really carry the value, is there a control VyQL did not model.
   Do not stop at the first that resolves.

Every verdict carries **counterevidence** (what argues the other way, including
when you still think it is real) and **proof gaps** (what the code could not
settle). Unresolved is a legitimate outcome if you name the gap.

## 6. Reproduce

Only when asked, and only for a finding that survived verify. A reproduction is a
failing test or a local request showing the path is real. It is not an exploit.

Three rules, not negotiable:

- **Ask first**, and say where it runs.
- **Local only.** Never a deployed host, a staging environment, or any address
  the user has not confirmed is theirs.
- **Writing it is the deliverable.** Running it is the user's call.

It proves the path is reachable with the input the analyzer claimed. Not the
blast radius, not production exploitability.

`references/reproduce.md` has the forms and what to do when there is nothing to
reproduce.

## Record the verdict, or it is lost

Triage that lives only in the conversation is gone the moment it ends, and the
next scan reports all of it again. Offer to write the verdicts into a baseline:
`references/baseline.md`.

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

`references/commands.md`.
