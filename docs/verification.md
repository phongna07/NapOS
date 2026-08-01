# Verification Guide

## 1. Host checks

```bash
make doctor
```

Every line must end in an `[ OK ]` result. A sudo prompt is expected. The mount
test creates and immediately removes a 64 KiB temporary `tmpfs` under `/tmp`.

## 2. Source authentication

```bash
make fetch
```

Confirm the output shows:

- Linux Mint signing fingerprint
  `27DEB15644C6B3CF3BD7D291300F846BA25BAE09`.
- A valid detached signature for `sha256sum.txt`.
- The pinned Cinnamon ISO SHA-256.
- Google Linux signing fingerprint
  `EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796`.
- A Google Chrome stable version whose `.deb` matches Google's signed repository
  metadata.
- An authenticated ISO below `cache/downloads/`.

A second invocation should reuse the ISO and a still-current authenticated
Chrome package. Google metadata is refreshed on every fetch so a newly released
stable package is selected automatically. If either cached input changes, the
workflow quarantines it and downloads a new copy.

## 3. Development build

```bash
make dev
```

Successful output reports the ISO path, size, SHA-256, build ID, and log path.
The build must not leave mounts below `work/rootfs`:

```bash
findmnt -R ~/napos/work/rootfs
```

No output is expected after the build.

## 4. Artifact verification

```bash
make verify ISO=dist/NapOS-0.1.0-dev-cinnamon-amd64.iso
make inspect ISO=dist/NapOS-0.1.0-dev-cinnamon-amd64.iso
```

Verification requires:

- Matching SHA-256 sidecar.
- Volume ID `NAPOS_0_1_0`.
- Legacy BIOS and EFI El Torito entries.
- `/etc/napos-release` and NapOS 0.1.0 identity.
- Preserved Mint and Ubuntu technical codenames.
- English locale and Bangkok timezone.
- NapOS logo and wallpaper.
- Installer label `Install NapOS`.
- All selected desktop packages in `filesystem.manifest`.
- No Firefox, Firefox locale, Mint Chat, Celluloid, or LibreOffice package in
  `filesystem.manifest`.
- The resolved `google-chrome-stable` version, executable, desktop launcher,
  official APT source, and signing key inside the live SquashFS.
- Google Chrome assigned as the HTTP/HTML handler and present in Cinnamon's
  default panel launchers, with no remaining Firefox launcher.
- No `google-chrome-stable` entry in `filesystem.manifest-remove`, so the
  installed system retains Chrome.
- An unchanged `filesystem.manifest-remove` from the authenticated Mint ISO.
  Its Firefox locale entries are preserved upstream installer metadata and do
  not indicate that those packages remain in the customized SquashFS.

Inspection prints the SquashFS compression and the adjacent provenance JSON.
The JSON records the exact Chrome version, SHA-256, repository package path,
Google signing fingerprint, and package-removal policy hash used by the build.

## 5. Release build

After the development ISO passes VirtualBox testing:

```bash
make release
make verify ISO=dist/NapOS-0.1.0-cinnamon-amd64.iso
```

The release build uses XZ compression and can take substantially longer than
the LZ4 development build.
