# vyprai/claude-plugins

Claude Code plugins for [VyQL](https://github.com/vyprai/vyql), a multi-language
taint and graph security scanner.

```
/plugin marketplace add vyprai/claude-plugins
/plugin install vyql@vypr
```

## vyql

Scans a codebase for vulnerabilities and triages what comes back: it follows
tainted data from source to sink and names the neutralizing controls that are
missing, so a finding can be argued with rather than just believed.

The skill is model-invoked — ask for a security scan, an audit, or a check for
injection, XSS, SSRF, path traversal or hardcoded secrets, and Claude reaches for
it. It also covers judging whether a reported finding is real, which is where
most of the time goes on a real codebase.

It installs the `vyql` binary if it is missing, **after asking**. A security tool
that downloads and runs binaries without permission has the wrong instincts.

### Without Claude Code

`skills/vyql-security-scan/` follows the [Agent Skills](https://agentskills.io)
format — a `SKILL.md` with YAML frontmatter plus reference files. Any tool that
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
