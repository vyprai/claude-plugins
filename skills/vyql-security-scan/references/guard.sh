#!/bin/sh
# Refuse a dangerous command before it runs on the user's machine.
#
#   sh references/guard.sh '<command line>'
#
# Exit 0 and print nothing: the command is allowed.
# Exit 1 and print the reason to stderr: the command is refused, do not run it.
#
# This is a pure check with no model in it. The reproduce phase runs commands on
# the user's own working tree, network, and credentials, not in a sandbox, so a
# prose rule ("do not run it against anything you did not just create") is not
# enough on its own. An agent that has reasoned for twenty steps about a path
# traversal is exactly the thing that talks itself past a prose rule. Gate every
# command in the reproduce and exploit steps through this first:
#
#   sh references/guard.sh "$cmd" && sh references/vyql-run.sh "$cap" out -- $cmd
#
# The list is intentionally strict for a developer machine. It refuses more than
# a disposable container would, because the blast radius here is the user's tree,
# their LAN and VPN, and their cloud credentials. When a refusal is wrong for a
# case the user has explicitly approved, say what was refused and let the user
# decide, rather than editing the command to slip past the gate.
set -u
cmd=${1:-}
refuse() { echo "guard: refused — $1" >&2; exit 1; }

# Destructive filesystem and device writes.
# A recursive rm of any absolute path that is not under /tmp is refused. The
# reproduction worktree lives in /tmp, so a real teardown still passes.
if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+-[A-Za-z]*r[A-Za-z]*f|rm[[:space:]]+-[A-Za-z]*f[A-Za-z]*r|rm[[:space:]]+-r([[:space:]]|[A-Za-z]*[[:space:]])'; then
  for p in $(printf '%s' "$cmd" | grep -Eo '/[^[:space:]]*'); do
    case "$p" in
      /tmp|/tmp/*) : ;;
      *) refuse "recursive delete of an absolute path outside /tmp ($p)" ;;
    esac
  done
  printf '%s' "$cmd" | grep -Eq '[[:space:]]/[[:space:]]*$' && refuse "recursive delete of /"
fi
printf '%s' "$cmd" | grep -Eq 'dd[[:space:]].*of=/dev/' \
  && refuse "dd writing to a device"
printf '%s' "$cmd" | grep -Eq '>[[:space:]]*/(etc|usr|bin|sbin|boot|sys)/' \
  && refuse "redirect into a system directory"
printf '%s' "$cmd" | grep -Eq 'chmod[[:space:]]+[0-7]*7[0-7]*[[:space:]]+/' \
  && refuse "world-writable chmod on an absolute path"

# Remote code piped straight into a shell.
printf '%s' "$cmd" | grep -Eq '(curl|wget)[[:space:]].*\|[[:space:]]*(ba|z|da)?sh' \
  && refuse "piping a download into a shell"

# Fork bomb.
printf '%s' "$cmd" | grep -Eq ':\(\)[[:space:]]*\{.*:[[:space:]]*\|[[:space:]]*:.*\}' \
  && refuse "fork bomb"

# The user's credentials and durable config. These never belong in a reproduction.
printf '%s' "$cmd" | grep -Eq '(~|\$HOME)/\.(ssh|aws|kube|docker/config|config/gcloud)' \
  && refuse "touching credential or cloud-config files"
printf '%s' "$cmd" | grep -Eq '\.git/config' \
  && refuse "writing .git/config"

# Anything that leaves the machine or changes remote state.
printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push' \
  && refuse "git push — a reproduction never publishes"
printf '%s' "$cmd" | grep -Eq 'docker[[:space:]]+run[^\n]*-v[[:space:]]*/(:|[[:space:]]|$)' \
  && refuse "docker mounting the host root"

# Network egress during the exploit step is local only. A curl or wget to any
# address that is not loopback is reaching real infrastructure — the exact shape
# of an SSRF proof fired against live metadata. Prove reachability against a
# listener started on localhost instead.
if printf '%s' "$cmd" | grep -Eq '(curl|wget|nc|ncat)[[:space:]]'; then
  # Allow only loopback hosts. If a non-loopback host or a bare scheme appears, refuse.
  hosts=$(printf '%s' "$cmd" | grep -Eo 'https?://[^/ "'\'']+' | sed -E 's#https?://##; s#:.*##')
  for h in $hosts; do
    case "$h" in
      127.0.0.1|localhost|0.0.0.0|::1|\[::1\]) : ;;
      *) refuse "network fetch to a non-loopback host ($h) — keep exploit traffic on localhost" ;;
    esac
  done
fi

exit 0
