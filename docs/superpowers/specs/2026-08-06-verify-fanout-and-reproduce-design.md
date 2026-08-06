# Verify fan-out and reproduction against running code

**Status:** approved, not yet implemented
**Scope:** `vyprai/claude-plugins` only. No `vyql` CLI change is required.

## What this is

The `vyql-security-scan` skill runs one flow:

```
scope → scan → coverage → triage → verify → reproduce
```

The last two phases are shallow today. Verify walks findings one at a time in the
main conversation. Reproduce writes a failing test and stops. This changes both:
verify fans out across subagents grouped by rule family, and reproduce boots the
application from a clean worktree and exploits it.

The proprietary platform does the same thing with server-side infrastructure: an
asyncio fan-out, a Claude Code verification agent against a cloned repository, and
a Docker executor targeting official images. This is the laptop version. It
carries no infrastructure, and the only things it needs are `vyql`, `git`, and
whatever container runtime the developer already has.

## Why the platform's design does not transfer directly

Two differences drive every decision here.

**The platform's executor targets upstream images**, because it proves CVEs
reproduce against published software. This skill proves *the developer's own code*
is exploitable, so the target has to be the worktree.

**The platform runs on disposable servers.** This runs on a machine with the
developer's real database, real credentials and real network. Isolation is not a
nicety here; it is what makes the feature shippable.

## Decisions

| Question | Decision |
|---|---|
| Target of a reproduction | An instance booted from a clean worktree, never one the developer is already running |
| Fan-out grouping | Rule family, ordered by the highest severity in each family |
| When the boot fails | Write the failing test, and say the boot did not come up |
| Retry a failed boot | No |

### Why rule family and not severity

Triage has already ordered by severity, so severity is spent by the time verify
starts.

The verify questions are family-shaped. What makes an injection real is not what
makes a path traversal real, which is why `references/triage.md` is already split
that way. An agent holding one family reads one section and applies it several
times instead of context-switching.

The stronger reason is that **systematic false positives arrive as a family**. A
repository with a sanitizer VyQL does not model will not produce one wrong
finding; it produces every path-traversal finding that flows through that helper.
One agent seeing all six spots the shared `safeJoin()` in a single pass. Split
across severity buckets, several agents each conclude "looks real" and nobody sees
the pattern. That is the failure mode that gets a scanner dismissed.

### Why a fresh boot and not the running instance

A development instance is usually wired to a real local database with real rows.
A path traversal proved by reading `/etc/passwd` is harmless. A SQL injection
proved by dropping a table is not, and the agent cannot reliably tell which it has
written before it runs it.

A fresh instance means the worst outcome is a broken throwaway container.

## Architecture

Nothing new is deployed. The skill orchestrates tools that already exist.

```
SKILL.md                      the flow, the bounds, the rules that must hold
references/verify.md          per-finding procedure (exists; gains fan-out)
references/reproduce.md       boot, exploit, teardown (exists; gains the boot path)
references/triage.md          per-family judgment (exists, unchanged)
```

### Verify

1. Read `vyql scan --format json`. Group findings by rule family, taken from the
   middle segment of the rule id: `VYQL-INJ-004` is family `INJ`.
2. Order families by the highest severity each contains.
3. Spawn one subagent per family, **at most six per run**. Each receives its
   family's findings, the repository path, and the family's section of
   `references/triage.md`.
4. Each subagent returns verdicts in the format `SKILL.md` already specifies:
   surface and source trust, the three questions, counterevidence, proof gaps.
5. Families beyond the cap are reported as deferred, by name, with an offer to
   run the next batch.

Six is a cost bound, not a technical one. Fourteen families exist in the corpus,
and fourteen subagents is a token surprise large enough that someone uninstalls
the skill over it.

**Subagents are not assumed.** The fan-out needs a subagent capability. Where
there is none, the same procedure runs sequentially in the main loop, and the
skill says so rather than failing. This matters because `skills/` is a plain
`SKILL.md` and the repository claims any agent can read it.

### Reproduce

Only for a finding that survived verify, and only when asked.

1. `git worktree add` a clean checkout at the scanned commit.
2. Look for a runnable definition: `compose.yaml`, `docker-compose.yml`,
   `Dockerfile`.
3. Boot with throwaway volumes, bound to localhost, on an ephemeral port.
4. Send the exploit. Capture the response as evidence.
5. Tear down: `compose down -v`, then remove the worktree.
6. If step 2 or 3 fails, write the failing test instead and say the boot did not
   come up.

The worktree earns its place twice over: it is the exact commit that was scanned,
so the finding's line numbers still line up, and the developer's uncommitted work
cannot change the result.

## Safety rules

These are requirements, not guidance.

- **Ask before booting anything**, and say what will be started.
- **Never attach to an instance the developer is already running.**
- **Never mount the developer's real environment.** A clean worktree has no
  `.env`. If the application only boots with real credentials, that is a failed
  boot and the fallback applies.
- **Tear down on every exit path**, including failure. A container holding a port
  or a stray worktree costs more trust than a wrong finding does.
- **Network egress is not isolated.** A throwaway container still sits on the
  developer's machine and their network. An SSRF proof that fetches
  `169.254.169.254` or an internal hostname is reaching real infrastructure. The
  target of an exploit must be the booted instance itself. Prove an SSRF by
  showing the request is *issued*, against a listener the skill controls on
  localhost. If that cannot be done, it is a proof gap, not a reason to fire the
  request and see what happens.

## Failure handling

| Situation | Behaviour |
|---|---|
| No runnable definition found | Write the failing test. Say the boot did not come up. |
| Boot fails | Same. One attempt, no retry: a cold boot needing a seeded database burns minutes to reach the same fallback. |
| Exploit does not reproduce | **Not** a false positive. The boot may be misconfigured, the route unregistered, the payload wrong. Report unresolved with what was tried. |
| Exploit reproduces | The path is reachable with that input. Not impact, and not a verdict on other findings in the family. |
| A subagent errors | Its family is **unverified**, and that is stated. Silently dropping a family turns six findings into four with nobody noticing. |
| Teardown fails | Report it loudly with the container and worktree names, so the developer can clean up. |

## Testing

Two fixture repositories under `fixtures/`:

- `bootable/`: compose definition, a real path traversal, boots cold with no
  external dependency. Exercises the full path through exploit and teardown.
- `unbootable/`: a real finding and a compose file that cannot start without
  credentials. Exercises the fallback, which is the more common path in practice.

`scripts/check-skills.py` already fails when the skill names a CLI flag that does
not exist, and CI runs it weekly against the current release. That keeps the
commands honest. Beyond that, a skill is verified by running it, which is why the
fixtures matter more than assertions do.

## Out of scope

- **Any `vyql` CLI change.** `scan --format json` already emits `rule`,
  `severity`, `path`, `fp`, `source` and `sink`, and the family is derivable from
  the rule id. Nothing here needs the engine to change.
- **microVMs.** Containers are the isolation boundary. A microVM would be a
  stronger one, but it is infrastructure the developer would have to install, and
  the threat this defends against is the developer's own data rather than a
  hostile exploit escaping.
- **Fixing findings.** The skill proposes a control and does not edit code. That
  stays true.
