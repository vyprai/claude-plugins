# Choosing what to scan

Read this when working through phase 1 of `SKILL.md`.

| The user is asking | Scope |
|---|---|
| "audit this repo", "is this codebase secure" | the whole tree |
| "review this PR", "did my change introduce anything" | the diff |

**The diff case is different and matters.** On a codebase with an existing
backlog, scanning the whole tree at review time buries the two findings the
change actually introduced under two hundred it did not. Scan both sides and
diff:

```sh
base=$(git merge-base HEAD origin/main)          # or the PR's base ref
git worktree add -q /tmp/vyql-base "$base"
vyql scan -fail-on none --format json /tmp/vyql-base > /tmp/before.json
vyql scan -fail-on none --format json .           > /tmp/after.json
vyql diff /tmp/before.json /tmp/after.json
git worktree remove /tmp/vyql-base --force
```

**Use a worktree, never `git stash`.** Stashing puts the user's uncommitted work
somewhere they did not ask for it, and if anything fails between the stash and
the pop it stays there silently. A worktree is a separate checkout: the working
tree is untouched whatever happens, and a leftover one is harmless.

`diff` keys on the finding fingerprint, which is anchored to rule and location
rather than line number, so moving a function does not read as new findings.
Report the added ones. Mention removed ones only if the user is checking a fix.
