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
CHROME_DOWNLOAD_DIR="$CACHE_DIR/downloads/google-chrome"
ONLYOFFICE_DOWNLOAD_DIR="$CACHE_DIR/downloads/onlyoffice"
BASE_CACHE_DIR="$CACHE_DIR/base/$BASE_ISO_SHA256"
WORK_DIR="$PROJECT_ROOT/work"
ISO_TREE="$WORK_DIR/iso-tree"
ROOTFS="$WORK_DIR/rootfs"
META_DIR="$WORK_DIR/meta"
BASE_REFERENCE_DIR="$META_DIR/base-reference"
DIST_DIR="$PROJECT_ROOT/dist"
CONFIG_DIR="$PROJECT_ROOT/config"

# These shared readonly values are consumed by scripts that source this library.
# shellcheck disable=SC2034
readonly PROJECT_ROOT CACHE_DIR DOWNLOAD_DIR CHROME_DOWNLOAD_DIR ONLYOFFICE_DOWNLOAD_DIR BASE_CACHE_DIR WORK_DIR
# shellcheck disable=SC2034
readonly ISO_TREE ROOTFS META_DIR BASE_REFERENCE_DIR DIST_DIR CONFIG_DIR

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

is_github_actions() {
    [[ "${GITHUB_ACTIONS:-false}" == "true" ]]
}

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
    [[ "$GOOGLE_CHROME_PACKAGE" == "google-chrome-stable" ]] || die "Unexpected Google Chrome package name."
    [[ "$GOOGLE_CHROME_ARCH" == "amd64" ]] || die "Google Chrome input must target amd64."
    [[ "$GOOGLE_CHROME_DEB_URL" == "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" ]] ||
        die "Unexpected Google Chrome download URL."
    [[ "$GOOGLE_CHROME_APT_URL" == "https://dl.google.com/linux/chrome/deb" ]] ||
        die "Unexpected Google Chrome APT metadata URL."
    [[ "$GOOGLE_CHROME_SIGNING_KEY_URL" == "https://dl.google.com/linux/linux_signing_key.pub" ]] ||
        die "Unexpected Google Linux signing-key URL."
    [[ "$(trim_fingerprint "$GOOGLE_CHROME_SIGNING_FINGERPRINT")" =~ ^[A-F0-9]{40}$ ]] ||
        die "Invalid Google Linux signing fingerprint."
    [[ "$GOOGLE_CHROME_INSTALLED_APT_URI" == "https://dl.google.com/linux/chrome-stable/deb/" ]] ||
        die "Unexpected installed Google Chrome APT URI."
    [[ "$ONLYOFFICE_PACKAGE" == "onlyoffice-desktopeditors" ]] || die "Unexpected ONLYOFFICE package name."
    [[ "$ONLYOFFICE_ARCH" == "amd64" ]] || die "ONLYOFFICE input must target amd64."
    [[ "$ONLYOFFICE_DEB_URL" == "https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb" ]] ||
        die "Unexpected ONLYOFFICE download URL."
    [[ "$ONLYOFFICE_APT_URL" == "https://download.onlyoffice.com/repo/debian" ]] ||
        die "Unexpected ONLYOFFICE APT metadata URL."
    [[ "$ONLYOFFICE_APT_SUITE" == "squeeze" ]] || die "Unexpected ONLYOFFICE APT suite."
    [[ "$ONLYOFFICE_SIGNING_KEY_URL" == "https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE" ]] ||
        die "Unexpected ONLYOFFICE signing-key URL."
    [[ "$(trim_fingerprint "$ONLYOFFICE_SIGNING_FINGERPRINT")" =~ ^[A-F0-9]{40}$ ]] ||
        die "Invalid ONLYOFFICE signing fingerprint."
    [[ -f "$CONFIG_DIR/packages.txt" ]] || die "Missing package list: $CONFIG_DIR/packages.txt"
    [[ -f "$CONFIG_DIR/packages-remove.txt" ]] ||
        die "Missing package removal list: $CONFIG_DIR/packages-remove.txt"
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

verify_file_sha256_and_size() {
    local path=$1
    local expected_sha256=$2
    local expected_size=$3
    [[ -f "$path" ]] || return 1
    [[ "$expected_sha256" =~ ^[a-f0-9]{64}$ ]] || return 1
    [[ "$expected_size" =~ ^[0-9]+$ ]] || return 1
    [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || return 1
    [[ "$(sha256_of "$path")" == "$expected_sha256" ]]
}

primary_key_fingerprint() {
    local key_file=$1
    gpg --batch --show-keys --with-colons "$key_file" 2>/dev/null |
        awk -F: '$1 == "pub" { want_fingerprint=1; next }
            want_fingerprint && $1 == "fpr" { print $10; exit }'
}

release_file_metadata() {
    local release_file=$1
    local wanted_path=$2
    awk -v wanted="$wanted_path" '
        $0 == "SHA256:" { in_sha256=1; next }
        in_sha256 && $0 !~ /^ / { exit }
        in_sha256 && $3 == wanted { print $1 "\t" $2; found=1; exit }
        END { if (!found) exit 1 }
    ' "$release_file"
}

chrome_package_metadata() {
    local packages_file=$1
    awk -v wanted_package="$GOOGLE_CHROME_PACKAGE" -v wanted_arch="$GOOGLE_CHROME_ARCH" '
        BEGIN { RS=""; FS="\n" }
        {
            delete value
            for (i=1; i<=NF; i++) {
                separator=index($i, ": ")
                if (separator > 0) {
                    key=substr($i, 1, separator-1)
                    value[key]=substr($i, separator+2)
                }
            }
            if (value["Package"] == wanted_package && value["Architecture"] == wanted_arch) {
                if (value["Version"] == "" || value["Filename"] == "" ||
                    value["SHA256"] !~ /^[a-f0-9]{64}$/ || value["Size"] !~ /^[0-9]+$/) {
                    exit 2
                }
                print value["Version"] "\t" value["Filename"] "\t" value["SHA256"] "\t" value["Size"]
                found=1
                exit
            }
        }
        END { if (!found) exit 1 }
    ' "$packages_file"
}

onlyoffice_package_metadata() {
    local packages_file=$1
    local version filename sha256 size
    local selected_version="" selected_filename="" selected_sha256="" selected_size=""

    while IFS=$'\t' read -r version filename sha256 size; do
        [[ "$version" != "__INVALID__" ]] || return 1
        if [[ -z "$selected_version" ]] || dpkg --compare-versions "$version" gt "$selected_version"; then
            selected_version=$version
            selected_filename=$filename
            selected_sha256=$sha256
            selected_size=$size
        fi
    done < <(
        awk -v wanted_package="$ONLYOFFICE_PACKAGE" -v wanted_arch="$ONLYOFFICE_ARCH" '
            BEGIN { RS=""; FS="\n" }
            {
                delete value
                for (i=1; i<=NF; i++) {
                    separator=index($i, ": ")
                    if (separator > 0) {
                        key=substr($i, 1, separator-1)
                        value[key]=substr($i, separator+2)
                    }
                }
                if (value["Package"] == wanted_package && value["Architecture"] == wanted_arch) {
                    if (value["Version"] == "" || value["Filename"] == "" ||
                        value["SHA256"] !~ /^[a-f0-9]{64}$/ || value["Size"] !~ /^[0-9]+$/) {
                        print "__INVALID__"
                    } else {
                        print value["Version"] "\t" value["Filename"] "\t" value["SHA256"] "\t" value["Size"]
                    }
                }
            }
        ' "$packages_file"
    )

    [[ -n "$selected_version" ]] || return 1
    printf '%s\t%s\t%s\t%s\n' \
        "$selected_version" "$selected_filename" "$selected_sha256" "$selected_size"
}

validate_onlyoffice_deb() {
    local path=$1
    local expected_version=$2
    local expected_sha256=$3
    local expected_size=$4
    local package version architecture
    verify_file_sha256_and_size "$path" "$expected_sha256" "$expected_size" || return 1
    package=$(dpkg-deb -f "$path" Package 2>/dev/null) || return 1
    version=$(dpkg-deb -f "$path" Version 2>/dev/null) || return 1
    architecture=$(dpkg-deb -f "$path" Architecture 2>/dev/null) || return 1
    [[ "$package" == "$ONLYOFFICE_PACKAGE" ]] || return 1
    [[ "$version" == "$expected_version" ]] || return 1
    [[ "$architecture" == "$ONLYOFFICE_ARCH" ]]
}

validate_chrome_apt_source() {
    local source_file=$1
    [[ -f "$source_file" ]] || return 1
    [[ "$(grep -c '^Types:' "$source_file")" == 1 ]] && grep -qx 'Types: deb' "$source_file" || return 1
    [[ "$(grep -c '^URIs:' "$source_file")" == 1 ]] &&
        grep -qx "URIs: $GOOGLE_CHROME_INSTALLED_APT_URI" "$source_file" || return 1
    [[ "$(grep -c '^Suites:' "$source_file")" == 1 ]] && grep -qx 'Suites: stable' "$source_file" || return 1
    [[ "$(grep -c '^Components:' "$source_file")" == 1 ]] && grep -qx 'Components: main' "$source_file" || return 1
    [[ "$(grep -c '^Architectures:' "$source_file")" == 1 ]] &&
        grep -qx "Architectures: $GOOGLE_CHROME_ARCH" "$source_file" || return 1
    [[ "$(grep -c '^Signed-By:' "$source_file")" == 1 ]] &&
        grep -qx 'Signed-By: /usr/share/keyrings/google-chrome.gpg' "$source_file"
}

package_file_hash() {
    local package_file=$1
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$package_file" | sort | sha256sum | awk '{print $1}'
}

package_list_hash() {
    package_file_hash "$CONFIG_DIR/packages.txt"
}

package_remove_list_hash() {
    package_file_hash "$CONFIG_DIR/packages-remove.txt"
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
    printf '%s\n' "$NAPOS_VERSION|${BUILD_PROFILE:-unknown}|$BASE_ISO_SHA256|$(package_list_hash)|$(package_remove_list_hash)|${CHROME_DEB_SHA256:-unresolved}|${ONLYOFFICE_DEB_SHA256:-unresolved}|$(git_revision)" |
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
