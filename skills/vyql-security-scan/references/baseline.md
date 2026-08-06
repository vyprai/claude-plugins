# Recording verdicts in a baseline

Read this when the user wants triage to survive the conversation.

Triage that lives only in the conversation is gone the moment it ends, and the
next scan reports all of it again. Offer to write the verdicts down:

```sh
vyql scan -baseline .vyql-baseline.json .     # report only what is new
```

Entries are keyed on the finding fingerprint, anchored to rule and location
rather than line number, so a verdict survives edits elsewhere in the file.

```json
{ "fp": "cfb54bfb4024aa90", "verdict": "false-positive",
  "reason": "source is a build-time constant, not request data" }
```

`false-positive` and `accepted` are different claims. One says the finding is
wrong, the other says it is right and being lived with. Record which, and always
write the reason: an entry with no reason is a suppression nobody can review.

For a codebase with an existing backlog, `-baseline-write .vyql-baseline.json`
records everything as `accepted` so the gate fires only on new findings. Say
plainly that this accepts the backlog rather than fixing it.

**If the scan warns that baseline entries match nothing, surface it.** The code
they excused has changed, and a suppression that outlives its reason is worse
than no suppression.

