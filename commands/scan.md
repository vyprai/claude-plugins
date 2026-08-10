---
description: Run a resilient VyQL security scan and triage findings. Defaults to the current directory.
argument-hint: path | diff | a finding to verify (default: current directory)
---

Invoke the `vyql-security-scan` skill and run its flow.

Determine scope from the arguments:

- **No arguments:** scan the current working directory. This is the default and
  the common case.
- **A path:** scope the scan to that path.
- **`diff`:** use the diff recipe - scan the pending change against its base and
  report only what the change introduced.
- **A pasted finding** (a rule id, a `path:line`, or another scanner's output):
  skip to the verify phase for that finding.

Arguments: $ARGUMENTS

Follow the skill's resilience protocol: run every vyql call through the
`vyql-run` time-boxer with a cap from the scope probe, and never retry an
identical failing command. Memory is vyql's concern; the skill bounds time.
