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
the Mint ISO when necessary, makes a fresh work tree, installs packages,
applies NapOS customization, builds an LZ4 SquashFS, preserves Mint's BIOS and
EFI boot equipment, verifies the result, and writes artifacts to `dist/`.

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

## Commands

| Command | Result and verification |
| --- | --- |
| `make help` | Prints the supported interface without network or root access. |
| `make doctor` | Checks WSL2, native storage, 30 GiB free space, tools, sudo, and temporary mount capability. |
| `make fetch` | Downloads Mint manifests and ISO, verifies Mint's signing fingerprint, GPG signature, signed SHA-256, and committed lock. |
| `make dev` | Builds and verifies a fresh LZ4 ISO. |
| `make release` | Builds and verifies a fresh XZ ISO. |
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
   the ISO checksum.
3. **Base cache:** extracts ISO content with `xorriso` and expands SquashFS once
   into a cache keyed by the authenticated ISO hash.
4. **Fresh work tree:** copies the immutable cache for every build so package
   changes never accumulate across builds.
5. **Customize:** installs VLC, GIMP, Flameshot, Git, Curl, Htop, and Vim;
   applies English/Bangkok defaults and original NapOS artwork.
6. **Clean:** removes APT/build state, restores DNS, and verifies all chroot
   mounts are gone.
7. **Pack:** creates LZ4 or XZ SquashFS and refreshes Casper size, package
   manifest, and ISO MD5 data.
8. **ISO:** maps only changed files into the authenticated Mint ISO and asks
   xorriso to replay the original BIOS/EFI boot equipment.
9. **Verify:** inspects the finished ISO before it is handed off for VM tests.

Builds are intentionally not claimed to be byte-reproducible: package versions
are resolved from live Linux Mint and Ubuntu repositories. The adjacent JSON
records the source and tool inputs for each build.

## NapOS identity policy

The user-facing product name is always **NapOS**. Machine identifiers and paths
use lowercase `napos`; the ISO volume ID is `NAPOS_0_1_0`.

NapOS preserves `ID=linuxmint`, Mint 22.3 codename `zena`, Ubuntu codename
`noble`, `/etc/lsb-release`, and the upstream APT sources so Mint's package and
repository tools continue to work.

## Testing and recovery

- [Detailed verification](docs/verification.md)
- [Troubleshooting and recovery](docs/troubleshooting.md)
- [VirtualBox BIOS and UEFI checklist](docs/virtualbox.md)

## License

Original build scripts and NapOS artwork in this repository are licensed under
GPL-3.0-only. Linux Mint and installed packages retain their respective
licenses. No proprietary browser, office suite, chat client, or third-party
branding is bundled by this workflow.
