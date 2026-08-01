# NapOS ISO Build Workflow

NapOS is an independently maintained Linux Mint remix. This repository builds
NapOS 0.1.0 from an authenticated Linux Mint 22.3 Cinnamon amd64 ISO without
copying CaramOS code, branding, or assets.

The workflow is designed for Ubuntu on WSL2. Keep the repository in the native
Linux filesystem (`~/napos`), not under `/mnt/c`.

## Quick start

```bash
cd ~/napos
make doctor
make dev
```

`make dev` is the complete development workflow. It authenticates and caches
the Mint ISO, current Google Chrome stable package, and current ONLYOFFICE
Desktop Editors package and the pinned Windows 10 Dark Cinnamon theme; makes a
fresh work tree; installs selected packages,
downloads and installs the Microsoft TrueType core fonts after accepting their
EULA, removes Firefox, applies NapOS customization,
builds an LZ4 SquashFS, preserves Mint's BIOS and EFI boot equipment, verifies
the result, and writes artifacts to `dist/`.

Expected output:

```text
dist/NapOS-0.1.0-dev-cinnamon-amd64.iso
dist/NapOS-0.1.0-dev-cinnamon-amd64.iso.sha256
dist/NapOS-0.1.0-dev-cinnamon-amd64.build-info.json
dist/build-dev.log
```

For the smaller release image:

```bash
make release
```

Both commands keep the cached WSL2 workflow: the authenticated base is expanded
once below `cache/`, then copied into a fresh work tree for each local build.

## GitHub Actions

Pull requests and pushes to `main` run the non-networked `make test` suite on a
standard `ubuntu-24.04` runner. They do not build an ISO.

Release ISOs are built only when the **Build release ISO** workflow is started
manually from the Actions page. Select the `main` branch and choose **Run
workflow**. The workflow refuses other branches, reclaims unused hosted-runner
SDK space, builds the XZ release with `make release`, performs the normal ISO
verification, and uploads these files as one workflow artifact:

```text
NapOS-<version>-cinnamon-amd64.iso
NapOS-<version>-cinnamon-amd64.iso.sha256
NapOS-<version>-cinnamon-amd64.build-info.json
build-release.log
```

The artifact is retained for one day to limit storage usage on GitHub Free, so
download it promptly and verify it with `sha256sum -c`. The workflow cache holds
only the pinned Mint ISO and its isolated GPG state. Chrome, ONLYOFFICE, and
Fcitx5 Lotus are resolved from current signed repository metadata, and the
checksum-pinned theme archive is downloaded on every release; expanded root
filesystems and disposable work trees are never cached.

GitHub builds use a storage-efficient work path that expands the base directly
into `work/` and releases large intermediate trees as soon as they are no longer
needed. This behavior is selected only when `GITHUB_ACTIONS=true`; local WSL2
commands and their reusable base cache are unchanged.

## Commands

| Command | Result and verification |
| --- | --- |
| `make help` | Prints the supported interface without network or root access. |
| `make doctor` | Checks WSL2 or GitHub-hosted Ubuntu, native storage, 30 GiB free space, tools, sudo, and temporary mount capability. |
| `make fetch` | Authenticates and caches the Mint ISO, latest Chrome, ONLYOFFICE, and Fcitx5 Lotus amd64 `.deb` files, and the checksum-pinned Windows 10 Dark theme. |
| `make dev` | Fetches current authenticated inputs, then builds and verifies a fresh LZ4 ISO. |
| `make release` | Fetches current authenticated inputs, then builds and verifies a fresh XZ ISO. |
| `make verify ISO=...` | Rechecks SHA-256, volume, BIOS/EFI entries, embedded identity, packages, artwork, locale, timezone, and installer launcher. |
| `make inspect ISO=...` | Prints ISO, boot, SquashFS, NapOS release, and provenance details. |
| `make test` | Runs Bash syntax, ShellCheck, safety, checksum, package-profile, and capitalization tests. |
| `make clean-work` | Safely unmounts and removes disposable work state only. |
| `make clean-cache` | Removes authenticated downloads, expanded bases, and isolated Mint signing-key state. |

When `ISO=` is omitted, verification and inspection use the newest NapOS ISO
under `dist/`.

## Build stages

1. **Doctor:** fails early if the host cannot safely build an ISO.
2. **Fetch:** authenticates the signed Mint checksum manifest before trusting
   the ISO checksum, and authenticates Chrome, ONLYOFFICE, and Fcitx5 Lotus
   through their signed APT metadata and pinned signing-key fingerprints, then
   verifies the Windows 10 Dark theme against its committed size and SHA-256.
3. **Base cache:** extracts ISO content with `xorriso` and expands SquashFS once
   into a cache keyed by the authenticated ISO hash.
4. **Fresh work tree:** copies the immutable cache for every build so package
   changes never accumulate across builds.
5. **Customize:** installs VLC, Flameshot, CopyQ, Fcitx5 with its GTK/Qt
   frontends, the Microsoft TrueType core fonts, and the authenticated
   Google Chrome, ONLYOFFICE, and Fcitx5 Lotus `.deb` files; pre-accepts the
   Microsoft font EULA for the noninteractive build, downloads the checksummed
   font payload through Ubuntu's installer package, configures Lotus for every
   live and installed user; installs Windows 10 Dark system-wide and selects it
   only as the user-overridable GTK Applications theme; purges
   Firefox and its language packs, Mint Chat, Celluloid, and the complete
   LibreOffice suite; makes Chrome the default browser and ONLYOFFICE the
   default for Microsoft Office, RTF, and CSV files; and applies
   English/Bangkok defaults and original NapOS artwork.
6. **Clean:** removes APT/build state, restores DNS, and verifies all chroot
   mounts are gone.
7. **Pack:** creates LZ4 or XZ SquashFS and refreshes Casper size, package
   manifest, and ISO MD5 data.
8. **ISO:** maps only changed files into the authenticated Mint ISO and asks
   xorriso to replay the original BIOS/EFI boot equipment.
9. **Verify:** inspects the finished ISO before it is handed off for VM tests.

Builds are intentionally not claimed to be byte-reproducible: package versions
are resolved from live Linux Mint, Ubuntu, Google, ONLYOFFICE, and Fcitx5 Lotus repositories.
The adjacent JSON records the source and tool inputs for each build, including
the exact Chrome, ONLYOFFICE, and Fcitx5 Lotus versions and SHA-256 values, the
pinned Windows 10 Dark source metadata, plus hashes of the package installation
and removal policies. Repository additions are listed in `config/packages.txt`;
base-image removals are listed in `config/packages-remove.txt`.

## NapOS identity policy

The user-facing product name is always **NapOS**. Machine identifiers and paths
use lowercase `napos`; the ISO volume ID is `NAPOS_0_1_0`.

NapOS preserves `ID=linuxmint`, Mint 22.3 codename `zena`, Ubuntu codename
`noble`, `/etc/lsb-release`, and the upstream Mint APT sources. Chrome's
official signed APT source is added separately so installed systems receive
browser security updates. ONLYOFFICE is installed from the authenticated
website `.deb`; its repository is used only to authenticate metadata and is not
added to the finished system. Fcitx5 Lotus retains its fingerprint-pinned,
Noble/amd64-only APT source so installed systems receive input-method updates.

## Testing and recovery

- [Detailed verification](docs/verification.md)
- [Troubleshooting and recovery](docs/troubleshooting.md)
- [VirtualBox BIOS and UEFI checklist](docs/virtualbox.md)

## License

Original build scripts and NapOS artwork in this repository are licensed under
GPL-3.0-only. Linux Mint and installed packages retain their respective
licenses. Google Chrome is proprietary and subject to Google's terms; this
workflow is intended for private/internal images unless separate redistribution
permission applies. ONLYOFFICE Desktop Editors retains its AGPLv3 license.
The Microsoft TrueType core fonts are proprietary and subject to Microsoft's
EULA, which the image builder explicitly accepts. NapOS images containing those
fonts are intended for private/internal use; obtain legal review before public
redistribution.
