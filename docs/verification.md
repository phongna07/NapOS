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
- ONLYOFFICE signing fingerprint
  `E09CA29F6E178040EF22B4098320CA65CB2DE8E5`.
- An ONLYOFFICE Desktop Editors amd64 version whose official website `.deb`
  matches ONLYOFFICE's signed repository metadata.
- Fcitx5 Lotus signing fingerprint
  `321E097BA44B5A53DB8BA81D55991878A14D5828`.
- An Fcitx5 Lotus amd64 version whose `.deb` matches the signed Noble repository
  metadata.
- An authenticated ISO below `cache/downloads/`.

A second invocation should reuse the ISO and still-current authenticated Chrome,
ONLYOFFICE, and Fcitx5 Lotus packages. Vendor metadata is refreshed on every fetch so newly
released stable packages are selected automatically. If a cached package no
longer matches, the workflow quarantines it and downloads a new copy.

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
- Cinnamon menu and grouped application list centered by the system dconf
  defaults, with the remaining Mint panel applets preserved.
- CopyQ installed with a system-wide hidden autostart entry and a user-overridable
  Cinnamon `Super+V` shortcut that runs `copyq toggle`.
- Flameshot installed with a system-wide, user-overridable autostart entry that
  launches its tray application at desktop login.
- The authenticated `Windows-10-Dark` theme payload installed system-wide and
  selected for Cinnamon's Applications theme, with the Yaru mouse pointer and
  dark mode selected by default. These defaults remain user-overridable, and
  no icon, desktop-shell, or window-border theme is overridden.
- Installer label `Install NapOS`.
- All packages selected in `config/packages.txt` in `filesystem.manifest`.
- The `ttf-mscorefonts-installer` package plus its Arial and Times New Roman
  payload files inside the live SquashFS.
- No Firefox, Firefox locale, Mint Chat, Celluloid, or LibreOffice package in
  `filesystem.manifest`.
- The resolved `google-chrome-stable` version, executable, desktop launcher,
  official APT source, and signing key inside the live SquashFS.
- The resolved `onlyoffice-desktopeditors` version, executable, desktop
  launcher, and Microsoft Office MIME declarations inside the live SquashFS.
- The resolved `fcitx5-lotus` version, signing key, constrained APT source,
  input-method descriptor, Fcitx5 configuration tool, and GTK/Qt frontends.
- System-wide Fcitx5 environment variables and autostart, an English-first
  profile containing Lotus, and the per-login Lotus server bridge.
- ONLYOFFICE assigned to Word, Excel, PowerPoint, RTF, and CSV formats in both
  system MIME policies while existing PDF and OpenDocument defaults remain
  unchanged.
- Google Chrome assigned as the HTTP/HTML handler and present in Cinnamon's
  default panel launchers, with no remaining Firefox launcher.
- No `google-chrome-stable` entry in `filesystem.manifest-remove`, so the
  installed system retains Chrome.
- No `onlyoffice-desktopeditors` entry in `filesystem.manifest-remove`, so the
  installed system retains ONLYOFFICE.
- No `fcitx5-lotus` entry in `filesystem.manifest-remove`, so the installed
  system retains Lotus.
- No `ttf-mscorefonts-installer` entry in `filesystem.manifest-remove`, so the
  installed system retains the Microsoft core fonts.
- An unchanged `filesystem.manifest-remove` from the authenticated Mint ISO.
  Its Firefox locale entries are preserved upstream installer metadata and do
  not indicate that those packages remain in the customized SquashFS.

Inspection prints the SquashFS compression and the adjacent provenance JSON.
The JSON records the exact Chrome, ONLYOFFICE, and Fcitx5 Lotus versions,
SHA-256 values, repository package paths, signing fingerprints, the pinned
Windows 10 Dark theme URL, catalog commit, size, SHA-256, and license, and the
package-removal policy hash used by the build.

## 5. Release build

After the development ISO passes VirtualBox testing:

```bash
make release
make verify ISO=dist/NapOS-0.1.0-cinnamon-amd64.iso
```

The release build uses XZ compression and can take substantially longer than
the LZ4 development build.
