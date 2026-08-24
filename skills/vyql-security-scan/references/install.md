# Installing vyql

**Ask before running any of this.** Downloading and executing a binary on
someone's machine without asking is exactly what a security tool should not do.

Check first:

```sh
vyql version
```

## Install script (preferred)

```sh
curl -fsSL https://dl.vyprsec.ai/vyql/install.sh | sh
```

Detects the platform, verifies the published SHA-256, unpacks under
`~/.local/share/vyql` and puts `vyql` in `~/.local/bin`. Say what it does before
running it: piping a script into `sh` is worth a sentence of explanation.

Set `VYQL_VERSION`, `VYQL_INSTALL_DIR` or `VYQL_BIN_DIR` to change any of that.

## Homebrew

```sh
brew install vyprai/tap/vyql
```

## Container

No install at all, if the work can happen in a container:

```sh
docker run --rm -v "$PWD:/work" ghcr.io/vyprai/vyql scan .
```

Runs as a non-root user, so it leaves no root-owned files in the mounted tree.

## Release archive

When the machine should not run a script off the network. About 14 MB
downloaded, 200 MB extracted, nearly all of it the security knowledge base,
which is why the binary works with no further setup.

Detect the platform, then substitute below:

```sh
uname -s   # Darwin -> darwin, Linux -> linux
uname -m   # arm64/aarch64 -> arm64, x86_64/amd64 -> amd64
```

```sh
V=v0.4.0; P=darwin_arm64        # linux_amd64 | linux_arm64 | darwin_amd64 | darwin_arm64
curl -fsSLO https://github.com/vyprai/vyql/releases/download/$V/vyql_${V}_${P}.tar.gz
curl -fsSLO https://github.com/vyprai/vyql/releases/download/$V/vyql_${V}_${P}.tar.gz.sha256
shasum -a 256 -c vyql_${V}_${P}.tar.gz.sha256      # or sha256sum -c on Linux
tar -xzf vyql_${V}_${P}.tar.gz
```

**Do not skip the checksum step.** It is the only thing between a substituted
download and running it. The checksum is served from the same host as the
archive, so it catches a corrupted download rather than a compromised release.

The binary is at `vyql_${V}_${P}/bin/vyql`. It finds its data relative to its own
location, so it can be run from anywhere or put on `PATH`.

Windows is not published. Linux and macOS only, amd64 and arm64. On Windows, use
WSL or the [GitHub Action](https://github.com/marketplace/actions/vyql-security-scan).

## go install

For Go developers. Needs Go 1.26+ and a C toolchain, because the parsers are C
compiled by cgo.

```sh
go install github.com/vyprai/vyql/cmd/vyql@latest
```

State the real cost before suggesting it: this pulls roughly 950 MB into the
module cache, and the binary resolves its data from there, so `go clean
-modcache` leaves a working binary that cannot find its knowledge base.

## When an install method fails

Still ask first; a failed download is not license to try three more unprompted.
Present the ladder and let the user pick:

1. **Install script fails** (network, TLS, checksum mismatch): a checksum
   mismatch is a stop, not a retry - report it, do not work around it. For a
   transient network error, offer Homebrew or the release archive.
2. **Wrong architecture** in the archive name: re-derive from `uname -s`/`uname
   -m` and offer the matching asset, rather than retrying the same URL.
3. **No prebuilt asset for the platform** (Windows): WSL or the GitHub Action,
   named in this file.
4. **Last resort** `go install`: only for Go developers, and only after stating
   the ~950 MB module-cache cost already documented here.

Never retry an identical failing download. Change the method, the asset, or the
source, or ask.

## Version

The skill needs **v0.3.0 or newer**. It passes one `-exclude` per pattern, uses
`-flags with` where earlier builds spell it `-all`, and reads exit `3` as
"findings met the gate" where earlier builds report `1`. Against a v0.2.x build
those become unknown flags, and a gated scan reads as a scanner failure.

```sh
vyql version
```
