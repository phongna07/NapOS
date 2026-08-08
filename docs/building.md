# Building the vnmint Linux Mint image

The vnmint build workflow is supported on Ubuntu `amd64`, either installed
natively or running under WSL2. Ubuntu 24.04 is the reference host exercised by GitHub
Actions; other Ubuntu releases are accepted when they pass the same capability
checks. Ubuntu derivatives, other Linux distributions, WSL1, and non-`amd64`
hosts are not supported.

## Host requirements

Run builds as a normal user with interactive `sudo` access. The repository must
be on a Linux filesystem that preserves Unix ownership, permissions, links, and
extended attributes, with at least 30 GiB free. A Linux filesystem mounted
below `/mnt` is valid on native Ubuntu. Windows, NTFS, FAT, network, and other
metadata-incompatible filesystems are rejected.

On WSL2, keep the repository in the distribution filesystem, such as
`~/vnmint`, rather than on a Windows drive such as `/mnt/c`. Confirm that the
distribution uses WSL version 2 from PowerShell:

```powershell
wsl --list --verbose
```

Install the required Ubuntu packages explicitly:

```bash
sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
    bash coreutils curl diffutils dpkg file findutils git gnupg \
    initramfs-tools-core jq make mount rsync sed shellcheck \
    squashfs-tools sudo unzip util-linux xorriso
```

Fetching build inputs and customizing the chroot require internet access.
Routine `make test` validation is non-networked and does not require root.

## Local workflow

Clone the repository onto the supported Linux filesystem, then validate the
host before building:

```bash
cd ~/vnmint
make doctor
make dev
```

`make dev` authenticates and caches upstream inputs, prepares a fresh work
tree, builds an LZ4-compressed development ISO, and verifies the result. Use the
release profile when a smaller XZ-compressed image is required:

```bash
make release
```

Local native Ubuntu and WSL2 builds share the same strategy: an authenticated
base image is expanded once below `cache/`, then copied into a fresh `work/`
tree for each build. GitHub Actions instead expands directly into `work/` and
removes large intermediate files early to fit the hosted runner's storage
limit. That optimization is selected only when `GITHUB_ACTIONS=true`.

## Commands and artifacts

- `make fetch` authenticates and caches the pinned base ISO and third-party
  inputs without starting a complete build.
- `make verify ISO=dist/vnmint-...iso` verifies an existing image.
- `make inspect ISO=dist/vnmint-...iso` prints image metadata.
- `make clean-work` removes disposable build state while retaining downloads
  and the expanded base cache.
- `make clean-cache` also removes authenticated downloads and base caches.

Development builds write these files below `dist/`:

```text
vnmint-<version>-dev-cinnamon-amd64.iso
vnmint-<version>-dev-cinnamon-amd64.iso.sha256
vnmint-<version>-dev-cinnamon-amd64.build-info.json
build-dev.log
```

Release builds use the same names without the `-dev` suffix and write
`build-release.log`. Builds are not byte-reproducible because package versions
are resolved from live upstream repositories.

The `vnmint` prefix identifies generated artifacts only. The ISO volume ID,
live boot menus, installer, desktop artwork, Plymouth splash, and installed
operating-system identity remain Linux Mint.

Full local builds require interactive sudo authentication, mounts, networking,
and chroot operations. Agents and other non-interactive environments should use
`make test`; a human should run `make doctor` and `make dev` when validating a
native Ubuntu build end to end.
