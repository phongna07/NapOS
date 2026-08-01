# Repository Guidelines

## Project Structure & Module Organization

NapOS is a Bash/Make Linux Mint ISO remaster. `tools/napos-build` is the main CLI, with shared validation and safety helpers in `tools/lib/common.sh`. Settings live in `remix.conf`; `config/source.lock` pins authenticated upstream inputs and signing identities. `config/packages.txt` and `config/packages-remove.txt` define package additions and removals. `config/hooks/` performs chroot customization, while `config/overlay/` supplies artwork, desktop defaults, systemd configuration, and image-side helper executables. Tests are in `tools/tests/selftest.sh`; hosted-runner support is in `tools/ci/`, GitHub workflows are in `.github/workflows/`, and manual verification and VM guidance live under `docs/`. `cache/`, `work/`, and `dist/` are ignored generated state.

## Build, Test, and Development Commands

Run local ISO workflows from Ubuntu on WSL2, on a native Linux path, as a normal user. GitHub Actions uses Ubuntu 24.04 for non-networked CI and for manually dispatched release builds.

- `make help` lists the supported interface.
- `make doctor` checks tools, free space, sudo, mounts, and host suitability.
- `make fetch` downloads and authenticates the pinned Mint base ISO and third-party packages selected through signed repository metadata.
- `make test` runs the non-networked, non-root Bash syntax, ShellCheck, safety, configuration, package-policy, provenance, and branding self-tests.
- `make dev` creates and verifies the faster LZ4 development ISO.
- `make release` creates and verifies the smaller XZ release ISO.
- `make verify ISO=dist/NapOS-...iso` validates an existing artifact; `make inspect ISO=...` prints its metadata.

Use `make clean-work` for build state and `make clean-cache` only to remove downloads and base caches too.

### Agent validation constraint

Use `make test` for routine agent validation. Do not run `make dev` to validate code: the agent terminal is non-interactive and cannot complete the required `sudo` authentication. For the same reason, do not run `make doctor`, `make release`, or other full ISO build and cleanup paths that require `sudo`, mounts, or chroot operations. Leave interactive ISO builds to a human or the release workflow. Targeted non-root checks such as `bash -n`, `shellcheck`, and `make help` are safe when useful.

## Coding Style & Naming Conventions

Write Bash with `#!/usr/bin/env bash` and `set -Eeuo pipefail`. Use four-space indentation, `lower_snake_case` for functions and locals, and `UPPER_SNAKE_CASE` for shared values. Quote expansions, prefer arrays for argument lists, and use `--` before path operands where supported. New shell files and executable overlay helpers need the existing SPDX header. Keep the display name exactly `NapOS`, machine identifiers lowercase `napos`, and run `make test` before submitting.

## Testing Guidelines

Extend `tools/tests/selftest.sh` for behavior changes. Add focused `expect_success` or `expect_failure` cases and create fixtures beneath its `mktemp` directory. Include new shell entry points and executable overlay helpers in both syntax and ShellCheck coverage. Tests must remain non-networked and must not require root. There is no numeric coverage target; cover affected host guards, safe removal, configuration, fingerprints and checksums, signed package metadata, package add/remove policy, provenance, overlay behavior, and branding. Pull requests and pushes to `main` run this suite through `.github/workflows/ci.yml`; `.github/workflows/release.yml` is a manual, `main`-only ISO build.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style subjects such as `chore: remove gimp from packages`. Prefer `<type>: <imperative summary>` (`feat`, `fix`, `docs`, `test`, or `chore`) and keep each commit focused. Pull requests should explain intent and build impact, list validation commands, link relevant issues, and include screenshots for artwork or visible desktop changes. Do not commit generated ISOs, logs, hashes, caches, or work trees.

## Security & Configuration

Do not weaken signature, fingerprint, checksum, repository-origin, architecture, mount, chroot-cleanup, or safe-removal checks. Preserve the restrictions in `tools/ci/reclaim-github-disk.sh` that limit destructive runner cleanup to GitHub-hosted Ubuntu. Changes to `config/source.lock`, package policies, or authenticated third-party inputs must document the trusted upstream source and be reviewed carefully. Never commit generated ISOs, logs, hashes, downloads, expanded root filesystems, caches, or work trees.
