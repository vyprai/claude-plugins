# Writing a reproduction

Read this when working through phase 6 of `SKILL.md`.
The three rules in `SKILL.md` are not repeated here because they are not
optional; this file is the how.

Only when asked, and only for a finding that survived verify.

## Booting the application

A reproduction runs against an instance you started from a clean worktree. Never
against one the developer is already running: a development instance is wired to
a real database with real rows, and you cannot tell a harmless payload from a
destructive one before you run it.

```sh
commit=$(git rev-parse HEAD)
git worktree add -q /tmp/vyql-repro "$commit"
cd /tmp/vyql-repro
```

The worktree earns its place twice: it is the commit that was scanned, so the
finding's line numbers still line up, and the developer's uncommitted work cannot
change the result.

Look for a runnable definition, in this order: `compose.yaml`,
`docker-compose.yml`, `Dockerfile`. If none exists, ask whether one lives under
another name or what command starts the app. If there is still none, write the
test instead.

Boot it with throwaway state, bound to localhost:

```sh
docker compose up -d --wait
```

**One attempt.** Retrying a cold boot that needs a seeded database burns minutes
to reach the same fallback. Supplying missing environment is a new set of inputs,
not a retry, and is worth one more attempt.

## Sending the exploit

The target is the instance you just booted, on its own port, and nothing else.

Capture the response as evidence. A path traversal that returns the contents of
`/etc/passwd` from inside the container has proved the path is reachable.

**Network egress is not isolated.** The container sits on the developer's machine
and their network. An SSRF proof that fetches `169.254.169.254` or an internal
hostname is reaching real infrastructure from inside what looks like a sandbox.
Prove an SSRF by showing the request is *issued*, against a listener you started
on localhost. If that cannot be done, it is a proof gap, not a reason to fire the
request and see what happens.

## Tearing down

Every exit path, including failure:

```sh
docker compose down -v
cd - && git worktree remove /tmp/vyql-repro --force
```

If teardown fails, say so loudly with the container and worktree names. A
container holding a port or a stray worktree costs more trust than a wrong
finding does.

## What it proves

The path is reachable with the input the analyzer claimed. Not the blast radius,
not production exploitability, and not a verdict on the other findings in that
family.

An exploit that does **not** reproduce is not a false positive. The boot may be
misconfigured, the route unregistered, the payload wrong. Report it unresolved,
with what was tried.



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

