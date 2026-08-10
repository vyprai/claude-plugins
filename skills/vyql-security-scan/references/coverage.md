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
vyql bindings -lang javascript
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
