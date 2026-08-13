# Reporting coverage

Read this when working through phase 3 of `SKILL.md`.

The output ends with what was read, and warns about what was not:

```
scanned python:1 textpattern:1 — 9 finding(s)
warning: 15 file(s) matched no frontend and were not analysed (.zig 12, .cob 3)
```

**Never suppress that warning, and never list findings without it.** A clean
report over a tree that was mostly skipped looks exactly like a clean report over
a tree that was fully read. Run `vyql scan -coverage .` for the full account when
anything looks off.

The coverage account goes to **stderr**, along with every other diagnostic —
stdout carries only the report, so `-format json` and `-format sarif` stay
parseable. `vyql-run.sh` captures both streams into one file. If you redirect
stdout yourself, redirect stderr too or the account is lost.

`-coverage` also reports how much each `-exclude` pattern actually excluded. A
pattern marked `← matched nothing` is a filter that is not doing what whoever
wrote it believed, which is worth saying out loud before reporting a clean tree.

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

## Silence is not safety: name the binding gaps

A framework VyQL has no bindings for produces no findings for the same reason a
safe codebase does: nothing matched. Distinguish them. Detect what the repo
actually uses, then ask VyQL what it models.

```sh
# What frameworks/engines are in play (adjust per ecosystem).
cat package.json requirements.txt go.mod pom.xml Gemfile composer.json 2>/dev/null

# What VyQL models for the languages present, and whether a given framework is bound.
vyql definitions -kind bindings -lang javascript
vyql definitions -query flask
vyql definitions -query express
```

If a framework or templating engine the repo depends on is absent from the
bindings, VyQL was blind to it. Report it by name alongside coverage:

> No findings in what was analysed (python:14, javascript:3). But the tree uses
> Jinja2 and FastAPI, neither of which VyQL has bindings for, so its silence
> there means nothing. Treat those surfaces as unscanned.

This is the coverage-phase half of "VyQL's output is a hypothesis": on the
silence side, an unmodelled framework is a proof gap, not a clean result.

## Unscanned file types are unscanned, not clean

The `matched no frontend` warning lists extensions VyQL has no frontend for. On a
real repository these are often the highest-value surfaces: SQL migrations
(`.sql`), Terraform and other IaC (`.hcl`, `.tf`), shell, and templates. A scan
that read the Go and TypeScript but skipped 273 migrations and 9 Terraform files
has said nothing about the database or the infrastructure. State the unscanned
extensions by count, and say which surfaces they leave unexamined, so a reader does
not read "no findings" as covering the whole tree. Where it matters, point the user
at a tool that does read those files.

## The silent false negatives

Coverage names what VyQL could not parse. It cannot name what VyQL parsed but
mis-cleared. `references/blindspots.md` covers the harder silent case: an
over-broad **check** binding — one matching a bare name like `authenticate` or
`sanitize` — marks unrelated code as a neutralizing control and suppresses every
finding on the flows it dominates, with nothing in the output to show for it. Over
an attacker-facing surface, treat "no findings" as "not adjudicated" until the
important flows are read by hand. A clean scan is the start of the review, not the
end of it.
