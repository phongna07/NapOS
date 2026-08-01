# Troubleshooting and Recovery

## WSL2 or native-filesystem failure

Check the distribution mode from PowerShell:

```powershell
wsl --list --verbose
```

The Ubuntu row must show version `2`. If necessary, stop active WSL sessions
and run `wsl --set-version Ubuntu 2`. Keep this repository at `~/napos` inside
Ubuntu. A path beginning with `/mnt/c`, `/mnt/d`, or another Windows drive is
unsupported because Linux ownership, device nodes, links, and I/O performance
are required by the remaster process.

## sudo or mount-capability failure

Run the workflow as your normal WSL user. Do not run the entire build as root.
In an interactive Ubuntu terminal, confirm sudo first:

```bash
sudo -v
cd ~/napos
make doctor
```

`make doctor` creates and removes temporary bind and proc mounts. If that test
fails after successful authentication, stop other WSL activity, run
`wsl --shutdown` from PowerShell, reopen Ubuntu, and retry. Never pass a sudo
password on a command line or store it in this repository.

## GPG key or signature failure

Do not bypass authentication. Retry the network operation. If isolated GPG
state is damaged, run `make clean-cache` and `make fetch`. The workflow obtains
Mint's key from keys.openpgp.org and Google's key from its official Linux
endpoint, then verifies both committed primary-key fingerprints.

## ISO checksum mismatch

An existing invalid ISO is renamed with an `.invalid.TIMESTAMP` suffix before
redownload. Keep it only if you need to investigate transport or disk errors.
Never edit `config/source.lock` to match an untrusted file. Chrome package
checksum or identity mismatches are quarantined the same way and retried
against freshly authenticated Google repository metadata.

## Interrupted build or busy mount

Inspect mounts first:

```bash
findmnt -R ~/napos/work/rootfs
```

Then run:

```bash
make clean-work
```

The cleanup target unmounts known chroot mounts before deleting disposable
state. It refuses unsafe or still-mounted paths.

## APT failure in the chroot

Read `dist/build-dev.log`. Common causes are transient mirrors, DNS, or package
repository locks. The next `make dev` discards the failed rootfs and starts from
the immutable base cache, so manual repair inside the failed chroot is normally
unnecessary.

## Insufficient disk space

`make doctor` requires at least 30 GiB free. Use `make clean-work` to retain the
authenticated base, or `make clean-cache` to recover all build storage.

## Stale or unwanted cache

`make fetch` reuses only an ISO matching the signed manifest and committed hash,
and only a Chrome `.deb` matching the latest signed Google package metadata.
Use `make clean-cache` only when no build or fetch is running; it checks locks
and mount descendants before removing authenticated downloads, the immutable
base cache, and isolated GPG state. The next `make fetch` downloads and verifies
everything again.

## Concurrent build error

Only one build may use `work/`. Wait for the active build. If no process is
running, inspect mounts, run `make clean-work`, and retry.

## VirtualBox is slow while WSL2 is enabled

VirtualBox may run through Windows' Hyper-V backend because WSL2 requires the
Virtual Machine Platform. This can be slower. Do not disable that Windows
feature during a NapOS build; doing so disables WSL2 until it is re-enabled and
Windows is restarted.
