# vyprai/claude-plugins

Claude Code plugins for [VyQL](https://github.com/vyprai/vyql), a multi-language
taint and graph security scanner.

```
/plugin marketplace add vyprai/claude-plugins
/plugin install vyql@vypr
```

## vyql

Scans a codebase for vulnerabilities and triages what comes back. It follows
tainted data from source to sink and names the neutralizing controls that are
missing, so a finding can be argued with rather than just believed.

The skill is model-invoked. Ask for a security scan, an audit, or a check for
injection, XSS, SSRF, path traversal or hardcoded secrets, and Claude reaches for
it.

### What it looks like

A conversation, not a command. Each turn keeps the last one's context, so you
never restate which finding you mean:

```
you  audit this repo for security problems

     scanned python:14 javascript:3, 2 files unread (.kt)
     7 findings. 2 critical, 3 high, 2 medium.
     1. VYQL-INJ-002  critical  api/users.py:88  request body reaches a shell
     2. VYQL-PATH-001 high      api/files.py:23  query param reaches open()
     ...

you  verify the high ones

     4 families: INJ (2), PATH (3), CRY (1), CFG (1). Verifying all four,
     one agent each. Nothing deferred.

     INJ   1 real, 1 false positive
     PATH  3 false positives, all through the same startswith() guard
     CRY   1 real
     CFG   1 unresolved, needs to know whether debug mode ships

     The three PATH findings share a cause. That guard is a containment
     check VyQL does not model, so it is a binding gap, not three bugs.

you  what about the INJ one

     Real. api/users.py:88 is a request handler and the path carries the
     value with no escaping. Fix is core.ShellEscape: subprocess with a
     list rather than shell=True.

you  prove it

     Booting from a clean worktree at the scanned commit.
     POST /users/import with a payload of "; id" returns uid=0(root).
     Torn down.

you  fix it then

     One file, api/users.py, introducing subprocess with an argument list.
     Shall I?
```

A reproduction runs against your own machine and nothing else, and the skill asks
before executing one. Writing it is the deliverable; running it is your call.

The flow underneath is always the same, and you stop wherever you have your
answer:

```
scope → scan → coverage → list → verify → reproduce → fix
```

**Coverage comes before findings, every time.** A clean report over a tree that
was mostly skipped looks exactly like a clean report over a tree that was fully
read, and the skill will not list findings without saying which is which.

Verifying fans out, one agent per rule family, four at most. That grouping is
the point: a systematic false positive arrives as a whole family, and one agent
holding all of them spots the shared guard that no per-finding review would.

Three things it will not do: report a verified finding as proof that a bug is
exploitable, since VyQL is static and cannot run anything; install the `vyql`
binary, write a reproduction, or edit your code without asking first; and boot
anything against an instance you are already running, because that one is wired
to your real database. A security tool that
downloads and runs things unprompted has the wrong instincts.

### Without Claude Code

`skills/vyql-security-scan/` follows the [Agent Skills](https://agentskills.io)
format: a `SKILL.md` with YAML frontmatter plus reference files. Any tool that
reads that format can consume it directly; the `.claude-plugin/` manifests are
only needed for Claude Code's installer.

## Layout

```
.claude-plugin/marketplace.json   the catalog
.claude-plugin/plugin.json        the plugin manifest
skills/vyql-security-scan/        SKILL.md + references/
```

The plugin is kept here rather than in the VyQL repository so installing it
copies 32 KB instead of cloning a repository whose security knowledge base is
several hundred megabytes.

## Contributing

The skill documents VyQL's CLI, so it can fall out of step with it. If a flag or
an install path changed in [vyprai/vyql](https://github.com/vyprai/vyql) and this
still describes the old one, that is a bug here.

```sh
claude plugin validate .        # what the review pipeline runs
claude --plugin-dir .           # load it without installing
```

Apache-2.0.
