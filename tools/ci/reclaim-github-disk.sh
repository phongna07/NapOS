#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

[[ "${GITHUB_ACTIONS:-false}" == "true" ]] || {
    printf '[ERROR ] Disk reclamation is restricted to GitHub Actions.\n' >&2
    exit 1
}
[[ "${RUNNER_ENVIRONMENT:-}" == "github-hosted" ]] || {
    printf '[ERROR ] Disk reclamation is restricted to GitHub-hosted runners.\n' >&2
    exit 1
}
[[ -r /etc/os-release ]] || {
    printf '[ERROR ] Cannot identify the runner operating system.\n' >&2
    exit 1
}
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || {
    printf '[ERROR ] Disk reclamation is restricted to Ubuntu runners.\n' >&2
    exit 1
}

# shellcheck source=/dev/null
source "$PROJECT_ROOT/remix.conf"

printf '[NapOS] Disk space before reclaiming runner-only tools:\n'
df -h "$PROJECT_ROOT"

unused_paths=(
    /opt/ghc
    /opt/hostedtoolcache
    /opt/microsoft/powershell
    /usr/local/.ghcup
    /usr/local/lib/android
    /usr/local/share/powershell
    /usr/share/dotnet
    /usr/share/swift
)

for path in "${unused_paths[@]}"; do
    [[ -e "$path" || -L "$path" ]] || continue
    printf '[NapOS] Removing unused hosted-runner path: %s\n' "$path"
    sudo rm -rf -- "$path"
done

if command -v docker >/dev/null 2>&1; then
    sudo docker system prune --all --force --volumes || true
fi
sudo apt-get clean

available_kib=$(df -Pk "$PROJECT_ROOT" | awk 'NR == 2 { print $4 }')
required_kib=$((MIN_FREE_GIB * 1024 * 1024))

printf '[NapOS] Disk space after reclaiming runner-only tools:\n'
df -h "$PROJECT_ROOT"

(( available_kib >= required_kib )) || {
    printf '[ERROR ] GitHub runner has less than %s GiB available after cleanup.\n' \
        "$MIN_FREE_GIB" >&2
    exit 1
}
printf '[  OK  ] At least %s GiB is available for the ISO build.\n' "$MIN_FREE_GIB"
