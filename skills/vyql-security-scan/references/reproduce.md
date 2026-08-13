# Writing a reproduction

Read this when working through phase 6 of `SKILL.md`.
The three rules in `SKILL.md` are not repeated here because they are not
optional; this file is the how.

Only when asked, and only for a finding that survived verify.

## Gate every command before it runs

This phase runs commands on the user's own machine — their working tree, their
network, their credentials — not in a sandbox. The three rules in `SKILL.md` are
the intent; `references/guard.sh` is the intent as code, because a prose rule does
not stop an agent that has reasoned itself into "just this once". Pass every
command through the gate first, and run it only if the gate allows it:

```sh
sh references/guard.sh "$cmd" || exit 1   # refused: do not run it
sh references/vyql-run.sh "$cap" /tmp/step.out -- $cmd
```

The gate refuses recursive deletes outside `/tmp`, writes to system directories,
downloads piped into a shell, anything touching `~/.ssh`, `~/.aws`, cloud config
or `.git/config`, `git push`, docker mounting the host root, and any network fetch
to a host that is not loopback. That last one enforces "local only" as code: an
exploit request to a non-loopback address is reaching real infrastructure, which
is the exact shape of an SSRF proof fired at live metadata. When the gate refuses
a command the user has explicitly approved for their case, say what was refused
and let the user decide — never reword the command to slip past it.

## First: what are you reproducing against?

VyQL scans services and libraries alike, and they reproduce differently. Decide
this before booting anything, and it should match the surface verify already
recorded.

| Surface | Reproduction |
|---|---|
| a runnable service (web app, API, worker with an entry point) | boot it and exploit its interface |
| a library or package (no entry point of its own) | a test that calls the vulnerable API with attacker input |
| a missing control (hardcoded secret, weak cipher) | nothing to run; name the control, do not invent a test |

The library case is not a degraded service case. A library does not boot because
it has no `main`: the caller supplies the input, so the reproduction is a test
that plays the caller and passes the tainted value straight into the public API.
If the surface is a library, skip the boot section entirely and go to **Library
or package**, below.

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
docker compose up -d
```

**`docker compose up --wait` exits 0 for a container that is about to die.** It
returns once the container is running, which is before dependencies install and
before the process reads its configuration. Measured on a fixture that exits with
`KeyError: 'DATABASE_PATH'`: `--wait` returned 0 and `ps` reported `running`.

So poll for whichever comes first, the app answering or the container exiting:

```sh
port=$(docker compose port app 3000 | cut -d: -f2)
for _ in $(seq 1 30); do
  case "$(docker compose ps -a -format '{{.State}}' | head -1)" in
    exited) docker compose logs --tail 20; echo "boot failed"; break ;;
  esac
  curl -fsS -o /dev/null "http://127.0.0.1:$port/" && break
  sleep 2
done
```

On failure, read the logs before deciding what to do. `KeyError: 'DATABASE_PATH'`
is a question to ask the user, not a reason to give up.

**One attempt.** Retrying a cold boot that needs a seeded database burns minutes
to reach the same fallback. Supplying missing environment is a new set of inputs,
not a retry, and is worth one more attempt.

### When the boot does not come up

The three rules still hold: ask first, local only, writing the repro is the
deliverable. Work the boot as a ladder, not a single shot:

1. **No `compose.yaml`/`Dockerfile`:** ask whether one lives under another name
   or what command starts the app (the existing ask-with-a-decline-path). If
   there is still none, go to 4.
2. **Container exits immediately** with a missing-env error (`KeyError:
   'DATABASE_PATH'`): supplying the env is new input, not a retry, and is worth
   one more attempt. Name the variable and ask.
3. **Port already bound:** remap the published port and retry - a materially
   different command, so it is a legitimate adaptation, not a repeat.
4. **Terminal:** write the failing test instead. This is the common outcome and
   not a degraded one - say the boot did not come up and hand over the test.

One attempt per rung. Do not re-run an identical cold boot that needs a seeded
database; it burns minutes to reach the same fallback.

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

## Library or package: exercise the API directly

There is nothing to boot, so do not try to. Write a test in the library's own
framework that calls the public function the finding flows from, with the input
an attacker would control, and asserts the sink is not reached. The test is the
caller VyQL said the library trusts, so the test plays the attacker.

Run it from the clean worktree, in the project's own test runner, so the line
numbers and dependencies match the scanned commit.

A path traversal in a file-serving helper:

```python
def test_read_asset_rejects_traversal():
    # read_asset is the public API; the caller (this test) is the attacker.
    with pytest.raises(ValueError):
        lib.read_asset("../../etc/passwd")   # today returns the file's contents
```

A command injection in a task-runner library:

```python
def test_run_hook_does_not_shell_out(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    with pytest.raises(ValueError):
        lib.run_hook("; touch pwned")        # today reaches shell=True
    assert not (tmp_path / "pwned").exists()
```

A library reproduction carries an assumption the service case does not, and you
state it: the finding is real **for a caller that passes untrusted input to this
API**. That is the library's contract to document, not proof that any particular
consumer is exploitable. It matches the surface verify recorded: "real, but the
caller supplies the input."

If the library has no test suite, write the smallest standalone script that
imports it and calls the API the same way, and say a suite would be the better
home.

## What it proves

The path is reachable with the input the analyzer claimed. Not the blast radius,
not production exploitability, and not a verdict on the other findings in that
family. For a library, add: reachable **by a caller that supplies the input**.

An exploit that does **not** reproduce is not a false positive. The boot may be
misconfigured, the route unregistered, the payload wrong. Report it unresolved,
with what was tried.

**A degraded result is not a success.** If the proof did not land cleanly — the
boot came up but the route returned 404, the response was not captured, the
localhost listener recorded no request — say that in the same breath as the
result. A reproduction reported as clean while its proof capture silently failed
is worse than no reproduction, because it reads as evidence it is not. Name the
gap; an empty proof is a defect in the reproduction, not an absence of news.



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

