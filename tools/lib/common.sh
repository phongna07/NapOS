#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -Eeuo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${NAPOS_PROJECT_ROOT:-$(cd "$COMMON_DIR/../.." && pwd)}"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/remix.conf"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/config/source.lock"

CACHE_DIR="$PROJECT_ROOT/cache"
DOWNLOAD_DIR="$CACHE_DIR/downloads/$BASE_ISO_SHA256"
BASE_CACHE_DIR="$CACHE_DIR/base/$BASE_ISO_SHA256"
WORK_DIR="$PROJECT_ROOT/work"
ISO_TREE="$WORK_DIR/iso-tree"
ROOTFS="$WORK_DIR/rootfs"
META_DIR="$WORK_DIR/meta"
DIST_DIR="$PROJECT_ROOT/dist"
CONFIG_DIR="$PROJECT_ROOT/config"

# These shared readonly values are consumed by scripts that source this library.
# shellcheck disable=SC2034
readonly PROJECT_ROOT CACHE_DIR DOWNLOAD_DIR BASE_CACHE_DIR WORK_DIR
# shellcheck disable=SC2034
readonly ISO_TREE ROOTFS META_DIR DIST_DIR CONFIG_DIR

if [[ -t 1 ]]; then
    COLOR_RED=$'\033[31m'
    COLOR_GREEN=$'\033[32m'
    COLOR_YELLOW=$'\033[33m'
    COLOR_BLUE=$'\033[36m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_RESET=""
fi

log() { printf '%s[NapOS]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*"; }
ok() { printf '%s[  OK  ]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
warn() { printf '%s[ WARN ]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2; }
die() { printf '%s[ERROR ]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

trim_fingerprint() {
    tr -d '[:space:]' <<<"$1" | tr '[:lower:]' '[:upper:]'
}

validate_config() {
    [[ "$NAPOS_NAME" == "NapOS" ]] || die 'NAPOS_NAME must be exactly "NapOS".'
    [[ "$NAPOS_ID" == "napos" ]] || die 'NAPOS_ID must be exactly "napos".'
    [[ "$NAPOS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid NAPOS_VERSION: $NAPOS_VERSION"
    [[ "$ISO_VOLUME_ID" =~ ^[A-Z0-9_]+$ ]] || die "ISO_VOLUME_ID must contain only A-Z, 0-9, and underscore."
    (( ${#ISO_VOLUME_ID} <= 32 )) || die "ISO_VOLUME_ID exceeds the ISO-9660 32-character limit."
    [[ "$BASE_ISO_SHA256" =~ ^[a-f0-9]{64}$ ]] || die "Invalid pinned base ISO SHA-256."
    [[ "$(trim_fingerprint "$MINT_SIGNING_FINGERPRINT")" =~ ^[A-F0-9]{40}$ ]] || die "Invalid Mint signing fingerprint."
    [[ -f "$CONFIG_DIR/packages.txt" ]] || die "Missing package list: $CONFIG_DIR/packages.txt"
    [[ -d "$CONFIG_DIR/overlay" ]] || die "Missing overlay directory: $CONFIG_DIR/overlay"
}

assert_safe_path() {
    local target=${1:-}
    local allowed_root=${2:-}
    local resolved_target resolved_root

    [[ -n "$target" && -n "$allowed_root" ]] || return 1
    resolved_target=$(realpath -m -- "$target") || return 1
    resolved_root=$(realpath -m -- "$allowed_root") || return 1

    [[ "$resolved_target" != "/" ]] || return 1
    [[ "$resolved_target" != "$(realpath -m -- "$HOME")" ]] || return 1
    [[ "$resolved_target" != "$resolved_root" ]] || return 1
    [[ "$resolved_target" == "$resolved_root"/* ]] || return 1
}

assert_no_mounts_below() {
    local target resolved mount_target
    target=$1
    resolved=$(realpath -m -- "$target")
    while IFS= read -r mount_target; do
        [[ "$mount_target" == "$resolved" || "$mount_target" == "$resolved"/* ]] && return 1
    done < <(findmnt -rn -o TARGET 2>/dev/null || true)
    return 0
}

safe_remove_tree() {
    local target=$1
    local allowed_root=$2
    assert_safe_path "$target" "$allowed_root" || die "Refusing unsafe removal: $target"
    assert_no_mounts_below "$target" || die "Refusing to remove mounted path: $target"
    if [[ -e "$target" || -L "$target" ]]; then
        sudo rm -rf -- "$target"
    fi
}

sha256_of() {
    sha256sum "$1" | awk '{print $1}'
}

package_list_hash() {
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$CONFIG_DIR/packages.txt" | sort | sha256sum | awk '{print $1}'
}

git_revision() {
    git -C "$PROJECT_ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf 'uncommitted'
}

git_dirty() {
    if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null || true)" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

build_id() {
    printf '%s\n' "$NAPOS_VERSION|${BUILD_PROFILE:-unknown}|$BASE_ISO_SHA256|$(package_list_hash)|$(git_revision)" |
        sha256sum | cut -c1-16
}

output_iso_for_profile() {
    case "$1" in
        dev) printf '%s/NapOS-%s-dev-%s-%s.iso\n' "$DIST_DIR" "$NAPOS_VERSION" "$NAPOS_EDITION" "$NAPOS_ARCH" ;;
        release) printf '%s/NapOS-%s-%s-%s.iso\n' "$DIST_DIR" "$NAPOS_VERSION" "$NAPOS_EDITION" "$NAPOS_ARCH" ;;
        *) die "Unknown build profile: $1" ;;
    esac
}

latest_iso() {
    local result
    result=$(find "$DIST_DIR" -maxdepth 1 -type f -name 'NapOS-*.iso' -printf '%T@ %p\n' 2>/dev/null |
        sort -nr | head -n1 | cut -d' ' -f2-)
    [[ -n "$result" ]] || die "No NapOS ISO found in $DIST_DIR."
    printf '%s\n' "$result"
}

need_sudo() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        die "Run the workflow as your normal user, not root. It invokes sudo only when needed."
    fi
    log "Refreshing sudo credentials..."
    sudo -v || die "sudo authentication failed."
}

cleanup_mounts() {
    local root=${1:-$ROOTFS}
    [[ -d "$root" ]] || return 0
    sync 2>/dev/null || true
    for mount_path in "$root/dev/pts" "$root/dev" "$root/proc" "$root/sys"; do
        if mountpoint -q "$mount_path" 2>/dev/null; then
            sudo umount -R "$mount_path" 2>/dev/null || sudo umount -Rlf "$mount_path" 2>/dev/null || true
        fi
    done
}

require_clean_mount_state() {
    assert_no_mounts_below "$1" || die "Active mounts remain below $1. Run make clean-work after inspecting findmnt."
}

with_temp_dir() {
    mktemp -d "${TMPDIR:-/tmp}/napos.XXXXXXXX"
}

