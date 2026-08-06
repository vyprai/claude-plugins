# Writing a reproduction

Read this when working through phase 6 of `SKILL.md`.
The three rules in `SKILL.md` are not repeated here because they are not
optional; this file is the how.

Only when asked, and only for a finding that survived verify.

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

