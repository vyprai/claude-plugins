# Command reference

Read this when you need a command the phase text did not give you.

## Time-box the expensive ones

`scan`, `explain` and `graph` can hang on a large tree or a huge file, so run
them through the time-boxer in `references/scan.md`, never raw:

```sh
sh references/vyql-run.sh <cap> /tmp/vyql.out -- vyql scan -fail-on none -flags with .
```

`<cap>` comes from the scope probe (`references/scope.md`). You do not need
`-max-ram`: memory is vyql's concern and on Linux it bounds itself, time is the
skill's. The cheap read-only
queries below (`match`, `resolve`, `bindings`, `definitions`) are fine
unbounded, but if any hangs, wrap it the same way.

| Command | Answers |
|---|---|
| `vyql scan -fail-on none -flags with .` | what is wrong, everything reported |
| `vyql scan -coverage .` | what was read, skipped, and left unanalysed |
| `vyql scan -format json .` | findings as JSON, for `diff` |
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
