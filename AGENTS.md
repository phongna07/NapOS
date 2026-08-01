# Repository Guidelines

## Project Structure & Module Organization

NapOS is a Bash/Make Linux Mint ISO remaster. `tools/napos-build` is the main CLI; shared helpers are in `tools/lib/common.sh`. Settings live in `remix.conf`; `config/source.lock` pins upstream inputs, `config/packages.txt` defines added packages, and `config/hooks/` plus `config/overlay/` customize the image. Tests are in `tools/tests/selftest.sh`, with manual verification and VM guidance under `docs/`. `cache/`, `work/`, and `dist/` are ignored generated state.

## Build, Test, and Development Commands

Run the workflow from WSL2 on a native Linux path, as a normal user:

- `make help` lists the supported interface.
- `make doctor` checks tools, free space, sudo, mounts, and host suitability.
- `make fetch` downloads and authenticates the pinned Mint base ISO.
- `make test` runs Bash syntax checks, ShellCheck, and the safety/branding self-tests.
- `make dev` creates and verifies the faster LZ4 development ISO.
- `make release` creates and verifies the smaller XZ release ISO.
- `make verify ISO=dist/NapOS-...iso` validates an existing artifact; `make inspect ISO=...` prints its metadata.

Use `make clean-work` for build state and `make clean-cache` only to remove downloads and base caches too.

## Coding Style & Naming Conventions

Write Bash with `#!/usr/bin/env bash` and `set -Eeuo pipefail`. Use four-space indentation, `lower_snake_case` for functions and locals, and `UPPER_SNAKE_CASE` for shared values. Quote expansions, prefer arrays for argument lists, and use `--` before path operands where supported. New shell files need the existing SPDX header. Keep the display name exactly `NapOS`, machine identifiers lowercase `napos`, and run `make test` before submitting.

## Testing Guidelines

Extend `tools/tests/selftest.sh` for behavior changes. Add focused `expect_success` or `expect_failure` cases and create fixtures beneath its `mktemp` directory. Tests must remain non-networked and must not require root. There is no numeric coverage target; cover affected safety guards, configuration, checksums, package policy, and branding.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style subjects such as `chore: remove gimp from packages`. Prefer `<type>: <imperative summary>` (`feat`, `fix`, `docs`, `test`, or `chore`) and keep each commit focused. Pull requests should explain intent and build impact, list validation commands, link relevant issues, and include screenshots for artwork or visible desktop changes. Do not commit generated ISOs, logs, hashes, caches, or work trees.

## Security & Configuration

Do not weaken signature, fingerprint, checksum, mount, or safe-removal checks. Changes to `config/source.lock` must document the trusted upstream source and be reviewed carefully.
