#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=tools/lib/common.sh
source "$PROJECT_ROOT/tools/lib/common.sh"

failures=0

pass() { printf '[  OK  ] %s\n' "$1"; }
fail() { printf '[FAILED] %s\n' "$1" >&2; failures=$((failures + 1)); }

expect_success() {
    local description=$1
    shift
    if "$@"; then pass "$description"; else fail "$description"; fi
}

expect_failure() {
    local description=$1
    shift
    if "$@"; then fail "$description"; else pass "$description"; fi
}

validate_config
pass "Configuration validates with exact NapOS identity"

mapfile -t scripts < <(find "$PROJECT_ROOT/tools" "$PROJECT_ROOT/config/hooks" -type f -name '*.sh' -o -path "$PROJECT_ROOT/tools/napos-build" | sort)
for script in "${scripts[@]}"; do
    expect_success "Bash syntax: ${script#"$PROJECT_ROOT/"}" bash -n "$script"
done

if shellcheck -x "$PROJECT_ROOT/tools/napos-build" "$PROJECT_ROOT/tools/lib/common.sh" \
    "$PROJECT_ROOT/tools/tests/selftest.sh" "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh"; then
    pass "ShellCheck"
else
    fail "ShellCheck"
fi

safe_root=$(mktemp -d "${TMPDIR:-/tmp}/napos-selftest.XXXXXXXX")
trap 'rm -rf -- "$safe_root"' EXIT
mkdir -p "$safe_root/work/child"

expect_success "Safe child path is accepted" assert_safe_path "$safe_root/work/child" "$safe_root/work"
expect_failure "Allowed root itself is rejected" assert_safe_path "$safe_root/work" "$safe_root/work"
expect_failure "Filesystem root is rejected" assert_safe_path / "$safe_root/work"
expect_failure "Home directory is rejected" assert_safe_path "$HOME" "$safe_root/work"
expect_failure "Outside path is rejected" assert_safe_path "$safe_root/outside" "$safe_root/work"

mock_active_mount() {
    findmnt() {
        printf '%s\n' "$safe_root/work/child"
    }
    assert_no_mounts_below "$safe_root/work"
}
expect_failure "Active descendant mounts are rejected" mock_active_mount

exec 7>"$safe_root/build.lock"
flock -n 7
expect_failure "Concurrent lock holder is rejected" flock -n "$safe_root/build.lock" true
flock -u 7

invalid_name_config() (
    local NAPOS_NAME=Napos
    validate_config 2>/dev/null
)
expect_failure "Invalid display-name configuration is rejected" invalid_name_config

invalid_fingerprint_config() (
    # shellcheck disable=SC2030
    local MINT_SIGNING_FINGERPRINT=0000
    validate_config 2>/dev/null
)
expect_failure "Invalid signing fingerprint is rejected" invalid_fingerprint_config

# shellcheck disable=SC2031
if [[ "$MINT_SIGNING_FINGERPRINT" == "27DEB15644C6B3CF3BD7D291300F846BA25BAE09" ]]; then
    pass "Mint signing fingerprint equals the committed pin"
else
    fail "Mint signing fingerprint equals the committed pin"
fi

printf 'NapOS checksum fixture\n' >"$safe_root/payload"
expected=$(sha256sum "$safe_root/payload" | awk '{print $1}')
actual=$(sha256_of "$safe_root/payload")
if [[ "$actual" == "$expected" ]]; then
    pass "Checksum helper accepts intact data"
else
    fail "Checksum helper accepts intact data"
fi
printf 'tampered\n' >>"$safe_root/payload"
if [[ "$(sha256_of "$safe_root/payload")" != "$expected" ]]; then
    pass "Checksum helper detects tampering"
else
    fail "Checksum helper detects tampering"
fi

expected_packages=$'curl\nflameshot\ngit\nhtop\nvim\nvlc'
actual_packages=$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PROJECT_ROOT/config/packages.txt" | sort)
if [[ "$actual_packages" == "$expected_packages" ]]; then
    pass "Desktop-essential package profile is exact"
else
    fail "Desktop-essential package profile is exact"
fi

if rg -n 'Napos' "$PROJECT_ROOT/remix.conf" "$PROJECT_ROOT/config" >/dev/null; then
    fail 'Incorrect product spelling "Napos" exists in configuration or assets'
else
    pass "Branding capitalization is exact"
fi

if grep -q '>NapOS<' "$PROJECT_ROOT/config/overlay/usr/share/backgrounds/napos/napos-wallpaper.svg"; then
    pass "Wallpaper contains the NapOS wordmark"
else
    fail "Wallpaper contains the NapOS wordmark"
fi

for target in help doctor fetch dev release verify inspect test clean-work clean-cache; do
    grep -Eq "^${target}:" "$PROJECT_ROOT/Makefile" || fail "Missing Make target: $target"
done
pass "Required Make interface is present"

if sed -n '/^prepare_work_tree()/,/^}/p' "$PROJECT_ROOT/tools/napos-build" |
    grep -Fq "sudo rm -f -- \"\$ISO_TREE/casper/filesystem.squashfs\""; then
    pass "Read-only Casper SquashFS is removed with build privileges"
else
    fail "Read-only Casper SquashFS is removed with build privileges"
fi

if sed -n '/^write_iso_md5s()/,/^}/p' "$PROJECT_ROOT/tools/napos-build" |
    grep -Fq "mv -f -- \"\$temporary_md5\" \"\$ISO_TREE/md5sum.txt\""; then
    pass "Read-only ISO checksum manifest is replaced non-interactively"
else
    fail "Read-only ISO checksum manifest is replaced non-interactively"
fi

if (( failures > 0 )); then
    printf '\n%d self-test(s) failed.\n' "$failures" >&2
    exit 1
fi
printf '\nAll NapOS non-networked tests passed.\n'
