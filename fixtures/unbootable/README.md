# unbootable

A real SQL injection in an app that cannot boot from a clean checkout, because
`DATABASE_PATH` only exists in the developer's environment.

`vyql scan` reports `VYQL-INJ-203`, `-004`, `-001`, `-018` and a
`VYQL-SMELL-DATA`. Four findings in one family is deliberate: it gives the
fan-out something real to group.

This is the more common shape, so the fallback matters more than the boot. The
skill should ask for `DATABASE_PATH` before giving up, and offer the failing test
if it does not get one.

The configuration is read at import rather than in the handler, so the process
exits instead of serving 500s. `docker compose up --wait` still returns 0 here,
which is why the boot procedure polls rather than trusting the exit code.
