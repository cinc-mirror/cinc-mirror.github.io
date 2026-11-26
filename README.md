# cinc-mirror.github.io

Hosting for the mirror installers: [`install.sh`](install.sh) (POSIX) and
[`install.ps1`](install.ps1) (Windows PowerShell) are served from
https://cinc-mirror.github.io/ and replace
https://omnitruck.cinc.sh/install.sh and https://omnitruck.cinc.sh/install.ps1.

The mirror itself — the Rust binary that crawls, verifies and publishes packages
to GHCR — lives in **[rmoriz/cinc-mirror](https://github.com/rmoriz/cinc-mirror)**.
Go there for the build, the ledger, the configuration format, the commands and
the CI setup. This repository only carries the installers, so a package install
needs nothing but the two commands below.

Please open issues at
[rmoriz/cinc-mirror/issues](https://github.com/rmoriz/cinc-mirror/issues) rather
than here — that is where the mirror, the ledger and the installers are actually
maintained.

## Trademark / Remarks

This project is neither affiliated nor approved by Progress Chef and/or the Cinc
community project. Use at your own risk. Feel free to open issues but don't
expect a SLA. Service may stop/break at any time. Solaris? AIX? 10 year old OS
versions? Sorry, won't work.

## Usage/Installation

Metadata still comes from cinc.sh, only the packages come from ghcr.io. In the
metadata dump the upstream `url` line is followed by
`mapped to cinc-mirror url: ghcr.io/rmoriz/cinc-mirror/<project>@sha256:<digest>`,
so the mirror address is visible before anything is fetched; the blob is pulled
from there and the installer falls back to the upstream URL only if the mirror
cannot serve it.

`-P` (POSIX) and `-project` (PowerShell) name the product. Without it, `cinc`
is installed.

| `-P` / `-project` | installs |
| --- | --- |
| `cinc` (default) | Cinc Client |
| `cinc-auditor` | Cinc Auditor |
| `cinc-foundation` | Cinc Foundation |
| `cinc-server` | Cinc Server (Linux/x86_64 only) |
| `cinc-workstation` | Cinc Workstation |
| `omnibus-toolchain` | the Omnibus build toolchain |

Linux and macOS:

```bash
# Cinc Client (default)
curl -sSL https://cinc-mirror.github.io/install.sh | sudo bash

# Cinc Auditor
curl -sSL https://cinc-mirror.github.io/install.sh | sudo bash -s -- -P cinc-auditor

# Cinc Workstation
curl -sSL https://cinc-mirror.github.io/install.sh | sudo bash -s -- -P cinc-workstation

# Cinc Server
curl -sSL https://cinc-mirror.github.io/install.sh | sudo bash -s -- -P cinc-server

# Cinc Foundation
curl -sSL https://cinc-mirror.github.io/install.sh | sudo bash -s -- -P cinc-foundation

# Omnibus toolchain
curl -sSL https://cinc-mirror.github.io/install.sh | sudo bash -s -- -P omnibus-toolchain
```

`cinc-server` exists only for Linux/x86_64 — no macOS, Windows or arm64 build —
the server example needs an x86_64 host. All other products build for several
platforms and the installer picks the matching package.

Windows PowerShell (elevated):

```powershell
# Cinc Client
. { iwr -useb https://cinc-mirror.github.io/install.ps1 } | iex; install -project cinc

# Cinc Auditor
. { iwr -useb https://cinc-mirror.github.io/install.ps1 } | iex; install -project cinc-auditor

# Cinc Workstation
. { iwr -useb https://cinc-mirror.github.io/install.ps1 } | iex; install -project cinc-workstation

# Cinc Foundation
. { iwr -useb https://cinc-mirror.github.io/install.ps1 } | iex; install -project cinc-foundation

# Omnibus toolchain
. { iwr -useb https://cinc-mirror.github.io/install.ps1 } | iex; install -project omnibus-toolchain
```

Both installers accept the upstream flags, e.g. `-v 26.4.0` / `-version 26.4.0`
to pin a version, `-c current` for the current channel's integration builds, and
`-d /tmp/dl` / `-f file` (POSIX) or `-download_directory` / `-filename`
(PowerShell) to choose where the package is saved before it is installed.
`-s once` (POSIX) skips the install when the project is already present, and
`-WhatIf` (PowerShell) reports what would be downloaded and installed. `install`
is the upstream-compatible alias for `Install-Project`, so
`install -project cinc-workstation -channel current` works too.

**Requirements:**
- `curl` must be installed for the POSIX installer; the mirror fetch always uses
  it, even when metadata came in over `wget`
- The PowerShell installer needs an elevated shell because it installs the
  `.msi` via `msiexec`. The mirrored `.msi` packages can also be downloaded and
  installed directly (see [Windows](#windows)).
- The mirror follows the current major of each product, so older majors come
  from upstream once the installer falls back.

## Windows

Windows packages (`.msi`) are mirrored like every other platform. The PowerShell
installer at https://cinc-mirror.github.io/install.ps1 resolves metadata from
omnitruck.cinc.sh, fetches the package blob from GHCR first and falls back to the
upstream download URL when the mirror cannot serve it. It verifies the SHA-256
checksum before running `msiexec`:

```powershell
. { iwr -useb https://cinc-mirror.github.io/install.ps1 } | iex; install -project cinc
```

Like upstream, `install` accepts `-version`, `-channel`, `-architecture` and the
other omnitruck flags; `install -version 19` picks the latest 19.x release.

`Get-ProjectMetadata` returns the download URL and SHA-256 checksum the installer
would use, without installing anything. The mirrored `.msi` packages can also be
downloaded and installed directly.

## Why?

Proof of concept. OSUOSL is doing an awesome job, just their connection with
Cogent is terrible slow. In Germany you get speeds below 1Mbit/s which sucks on
CI/CD or mass rollouts. Why not offload such traffic to Microsoft GitHub(TM) ;)

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE)
file for details.
