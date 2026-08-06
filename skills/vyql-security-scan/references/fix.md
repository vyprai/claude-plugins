# Fixing a finding

Read this only after the user has asked for a fix, on a finding that survived
verify.

## Before touching anything

Name the files you would change and the control you would introduce, then wait.
The control comes from the finding's `unless` line: reporting it is the whole
point of the finding.

Never edit a finding that is unresolved or unverified. "It is probably real and
the fix is cheap" is how a scanner starts rewriting code nobody asked it to.

## The change

Make the smallest edit that introduces the control, in the idiom the repository
already uses. Look at how the codebase does it elsewhere before inventing a
pattern.

Not a refactor. Not a tidy-up of the surrounding lines. Not an unrelated
improvement noticed on the way past. A security fix that also reformats a file is
a security fix nobody can review.

One finding at a time unless the user asked for several. If two findings share a
root cause, say so and propose the single change rather than making the same edit
twice.

## Proving it

If a reproduction exists, re-run it. A test that failed before the edit and
passes after is the only evidence in this phase that means much.

Then re-scan, and say what it proves:

    The pattern stopped matching.

Not that the code is safe. A finding can stop firing because the fix worked,
because the shape changed enough to lose the binding, or because something
upstream now fails before reaching the sink. Re-scanning distinguishes none of
those, and reporting a green scan as proof of safety is the overclaim this skill
exists to avoid.
