# VyQL's blindspots, and how to triage a scan around them

Read this before verifying a scan that returned many findings. It explains why
VyQL produces false positives in families, how to retire a whole family with one
verdict instead of reading every finding, and — the harder half — where VyQL goes
silent on a real problem so that its clean report means nothing.

## Why this exists

VyQL asserts one thing per finding: **a tainted SOURCE reaches a SINK, and no
CONTROL on the path neutralizes it.** A finding is only as trustworthy as those
three labels. Every label is produced by a binding, and a binding covers many
call sites. When a binding mislabels, it mislabels **every** site that matches it.
So VyQL's errors do not arrive one at a time. They arrive as a family: one wrong
binding, one repeated CWE, hundreds of findings.

That is the property that makes triage fast. You do not judge 300 findings. You
find the handful of binding-level mistakes behind them and judge each once. The
false-positive rate on a polyglot codebase can be very high while the number of
distinct root causes stays small.

The blindspots come from three places VyQL's data cannot reach:

- a concept whose CWE does not fit the language or the specific API it was bound to;
- a binding that matches on a bare name and catches unrelated same-named APIs;
- a missing check binding, so the `unless` clause can never be satisfied and the
  finding can never be cleared.

Each has a signature you can read from the scan output or settle with one cheap
command, before reading any source. Work the structural signals first. They kill
the largest families for the least effort, and they never depend on the specific
project.

## Group by CWE, then by root cause

The scan output gives every finding a rule (`VYQL-INJ-002`) and a CWE (`CWE-78`).
Group by **CWE** first — that is the axis a reader acts on, and the axis a fix
lands on. Within a CWE, collapse findings that share a **root cause** into one
verdict. Two findings share a root cause when they share any of:

- the same rule and the same sink API (`json.Unmarshal` everywhere, `.exec` everywhere);
- the same taint source `file:line` (one mislabelled source, fanned out);
- the same `unless` line reading "none found anywhere on flows" (one orphaned sink).

One collapsed cluster gets one verdict, applied to every finding in it. Name the
count you are retiring: "CWE-502, 341 findings, all `json.Unmarshal` into a typed
struct — one verdict." A reader can check one judgment against one shape far faster
than 341 near-identical lines.

## The structural signals — cheap kills, run these first

Each of these settles a whole cluster from the scan output plus at most one grep.
None requires reading the flagged source line by line. None is specific to one
project. Apply them before the source-reading verification in `verify.md`.

### 1. The concept's CWE does not fit the language or the API

A binding can be authored perfectly and still be wrong, because the concept it
emits carries a CWE the language cannot express. The pattern is precise; the
meaning is imported from another language.

**Test.** State what the CWE needs to be exploitable, then ask whether *this API
in this language* can do it:

| CWE | Needs, to be real | Where it does not hold |
|---|---|---|
| CWE-502 deserialization | decode instantiates attacker-chosen types, or runs code during decode | Go `encoding/json` / `yaml.Unmarshal` into a declared struct; Rust `serde` into a typed target — no polymorphic construction, no gadget surface |
| CWE-1333 ReDoS | the regex engine backtracks | Go `regexp` and Rust `regex` are RE2 — linear time, no backtracking, categorically cannot blow up |
| CWE-78 command injection | a shell or command interpreter runs the value | a method named `exec` that is `RegExp.prototype.exec`, `String` methods, a DB cursor `.exec` — no process is started |

**Verdict.** If the language or API cannot express the CWE's mechanism, the
finding is a false positive, and the real defect is a concept mapped to a CWE it
does not deserve in that language. Report the binding gap.

**Safeguard against a false negative.** The same concept often has a genuinely
dangerous form in the same language. Go `encoding/gob` does register types; a
decode into `any` / `map[string]any` has a real type-confusion story; Python
`pickle` and `yaml.load`, Java `ObjectInputStream`, PHP `unserialize` are the real
CWE-502. Do not dismiss the CWE for the language — dismiss it for **this API
shape**. Read the sink to confirm the shape (typed target versus `any`, RE2 versus
PCRE) before you collapse the cluster.

### 2. The sink is a name collision, not the dangerous API

Bindings that match a bare, single-segment name with no receiver type and no
dependency gate fire on every same-named call. In the scan output the sink line
shows a bare predicate (`callee.path ~= "exec"`, `callee.method == "Create"`) with
no qualifier.

**Test.** Read the sink `file:line` and resolve what the callee actually is:

- is the dangerous package imported at all? A JS file with no `child_process`
  import has no command-execution sink, whatever `.exec` it calls.
- what is the receiver's type? `os.Create` is a file sink; an ORM's `.Create` on a
  `*gorm.DB` is a database insert and touches no filesystem. `database/sql` `.Query`
  on a `*sql.DB` is a SQL sink; a GraphQL client's `.Query` is not.

**Verdict.** If the matched call is a different API that happens to share the name,
the whole cluster is a false positive from an unqualified binding. Report it: the
fix is a receiver-type or dependency gate on the binding.

**Watch for the shadow case.** A pack sometimes contains both a precise binding
(receiver-qualified) and a broad one (bare name) for the same concept. The broad
one wins and the precise one is dead weight, so the qualification you would expect
to save you does not fire. The signature is the same — a bare predicate in the
sink line — and so is the verdict.

### 3. The source is a long-lived handle, not request data (single-source amplification)

A source emitted on a connection, client, context, or session object taints a
*handle*, not *data*. The handle flows into everything downstream, so one
imprecise source binding produces findings across packages that have no relation
to each other.

**Signature.** A large fraction of all findings trace to **one** source `file:line`.
Sort the findings by their source node; when one source accounts for hundreds of
sinks spanning unrelated packages, that is the tell.

**Test.** Is the labelled node request *data*, or a transport or session *handle*?
The bytes read from a websocket connection are attacker-controlled; the
`*websocket.Conn` returned by an upgrade call is not. A request object is data; the
client, context, or session it is carried in is not.

**Verdict.** One imprecise source is one false positive, not one per sink it
reached. Collapse the entire fan-out to a single verdict against the source. The
fix is to emit the source at the data — the read call, the parsed parameter — not
at the handle.

### 4. The `unless` clause is unsatisfiable — an orphaned sink

VyQL clears a finding when a check on the path emits the neutralizing control. If
**no binding in the language emits that check at all**, the `unless` clause can
never be satisfied. Every match on that sink is reported unclearable — the safe
code and the vulnerable code look identical in the output.

**Signature.** The `unless` line reads `not satisfied — none found anywhere on
flows`, and it reads that way for **every** finding of the class, in that language.

**Confirm it in one command.** Ask whether any check in the language neutralizes
the sink's threat:

```sh
vyql definitions -kind bindings -lang go | grep -i safededeserialization
# or, over a checked-out rules tree:
grep -rl "emit check core.SafeDeserialization" vyql/bindings/ | grep -E '/go/|/packages/go/'
```

No match means the control cannot be emitted for that language. The escape hatch
is closed by construction.

**Verdict — and this is the one that is easy to get wrong.** An orphaned sink does
**not** make the class all false positives. It makes VyQL's *safety verdict
uninformative*: VyQL flagged a shape and could not adjudicate it either way,
because it had no means to clear anything. A real vulnerability in that class would
be reported exactly the same. So do not suppress the class on the strength of the
`unless` line. Instead, stop trusting the "not satisfied" framing, and verify the
sink and source by reading the code, as in `verify.md`. The orphaned-sink signal
lowers your trust in VyQL's confidence; it does not raise or lower the finding.
Suppressing an orphaned-sink class wholesale is how a scanner blindspot becomes a
missed vulnerability.

### 5. The rule does not apply to this surface

Some findings are on code the rule was never meant to judge. These are settled by
the surface question in `verify.md`, applied to a whole cluster at once.

- **Wrong side of the boundary.** Server-posture rules — missing rate limit,
  missing authentication, mass assignment — asserted against a client SDK, a
  library, or an example. The control they ask for lives on the server; the flagged
  code is the caller. A finding of this class on library or SDK code is a false
  positive; the fix is a profile or reachability gate, not a code change.
- **Generated code.** Generated clients and stubs are dense with findings and, by
  most repo policies, cannot be hand-edited, so even a real finding there is not
  fixed in place. Detect them by marker — `// Code generated by ... DO NOT EDIT.`
  (Go), an `@generated` header, `openapi-generator` banners — and down-rank or
  exclude them. Say you did.
- **Test fixtures and examples.** Covered in `verify.md`'s surface table; the same
  collapse applies — one verdict for the cluster, not one read per finding.

### 6. Existing suppressions were ignored

A line the team already marked as reviewed should not be re-reported as new. Before
reporting a secret, an injection, or a crypto finding, check the flagged line and
its neighbours for an existing suppression from another tool:

```
//nolint:gosec        # Go, gosec
// #nosec             # Go, gosec
# noqa                # Python, flake8
// eslint-disable-next-line security/...   # JavaScript/TypeScript
```

A finding on a line that already carries a matching suppression is not a new
finding. Note it as already-triaged rather than raising it again. This is also a
strong signal for the secret family: the neighbours of a flagged constant often
carry `#nosec` while the flagged line is the one nobody needed to suppress, because
it was never a credential.

## The dependency (SCA) findings are a special case

VyQL's bundled advisory data is small, and its version comparison can be
mis-transcribed so that the gate runs backwards — clearing a genuinely outdated,
vulnerable version and flagging a current, fixed one. Treat every SCA finding as
unconfirmed until you check the dependency and version against a real advisory
source (OSV.dev, GHSA):

- a **flagged** dependency may be current and safe — confirm the CVE actually
  affects the pinned version before reporting it;
- more dangerous, a **cleared** dependency may be genuinely vulnerable — a clean
  SCA result is not evidence the dependencies are safe.

Say plainly that VyQL's SCA is not an advisory database and should not be the only
dependency check. Do not let a clean SCA pass stand as a dependency guarantee.

## The silent half: blindspots that hide real findings

Every signal above removes noise. This section is the opposite risk, and it is the
one the user cannot see for themselves: places where VyQL reports nothing because
it *could not look*, not because the code is safe. The whole reason this skill
verifies VyQL rather than trusting it is that a scanner's silence is not a clean
bill of health.

- **Over-broad check bindings suppress findings silently.** A check that matches a
  bare name — any function called `authenticate`, `validate`, `sanitize`, `escape`
  — marks unrelated code as a neutralizing control and clears every flow it
  dominates. Unlike an over-broad sink, nobody complains, because the tool simply
  stops reporting. You cannot see these from the output. The defence is posture:
  over an attacker-facing surface, read "no findings" as "not adjudicated", not as
  "safe", and confirm the important flows by hand.
- **Unmodelled frameworks and file types produce no findings for the same reason a
  safe codebase does.** SQL migrations, Terraform and other IaC, template engines,
  and frameworks with no bindings are simply unread. `coverage.md` covers how to
  name these; the point here is that their silence carries no information and must
  not be folded into a clean verdict.
- **Shallow language packs under-report.** The reference languages (Java, Python,
  JavaScript) are modelled deeply; others range down to call-and-concat coverage,
  and some are unqualified enough to miss real sinks as well as invent false ones.
  A quiet result in a shallow-pack language is weak evidence of safety.

State these as blindspots alongside the findings, with the same weight. A report
that lists what VyQL got wrong but hides what it could not see is only half honest.

## The order that keeps it fast and safe

1. Group findings by CWE; within each CWE, collapse by root cause.
2. Apply the structural signals (1–6 above) to each cluster, from the scan output
   plus cheap greps. Most large clusters are settled here without reading source
   per finding.
3. Send only the clusters that survive to the source-reading verification in
   `verify.md` — the three taint questions, one subagent per surviving cluster.
4. Name the silent blindspots with the findings, never after them.

Fast comes from steps 1–2 retiring the families. No false negatives comes from the
safeguards: verify the API shape before dismissing a CWE, never suppress an
orphaned-sink class, treat silence and cleared SCA as unadjudicated rather than
safe.
