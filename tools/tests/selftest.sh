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

mapfile -t scripts < <(
    find "$PROJECT_ROOT/tools" "$PROJECT_ROOT/config/hooks" \
        "$PROJECT_ROOT/config/overlay/usr/libexec" -type f \
        \( -name '*.sh' -o -path "$PROJECT_ROOT/tools/napos-build" \
            -o -path "$PROJECT_ROOT/config/overlay/usr/libexec/napos-fcitx5-lotus-user" \) | sort
)
for script in "${scripts[@]}"; do
    expect_success "Bash syntax: ${script#"$PROJECT_ROOT/"}" bash -n "$script"
done

if shellcheck -x "$PROJECT_ROOT/tools/napos-build" "$PROJECT_ROOT/tools/lib/common.sh" \
    "$PROJECT_ROOT/tools/tests/selftest.sh" "$PROJECT_ROOT/tools/ci/reclaim-github-disk.sh" \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh" \
    "$PROJECT_ROOT/config/overlay/usr/libexec/napos-fcitx5-lotus-user"; then
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

invalid_google_fingerprint_config() (
    # shellcheck disable=SC2030
    local GOOGLE_CHROME_SIGNING_FINGERPRINT=0000
    validate_config 2>/dev/null
)
expect_failure "Invalid Google signing fingerprint is rejected" invalid_google_fingerprint_config

invalid_onlyoffice_fingerprint_config() (
    # shellcheck disable=SC2030
    local ONLYOFFICE_SIGNING_FINGERPRINT=0000
    validate_config 2>/dev/null
)
expect_failure "Invalid ONLYOFFICE signing fingerprint is rejected" invalid_onlyoffice_fingerprint_config

invalid_fcitx5_lotus_fingerprint_config() (
    # shellcheck disable=SC2030
    local FCITX5_LOTUS_SIGNING_FINGERPRINT=0000
    validate_config 2>/dev/null
)
expect_failure "Invalid Fcitx5 Lotus signing fingerprint is rejected" \
    invalid_fcitx5_lotus_fingerprint_config

invalid_theme_url_config() (
    # shellcheck disable=SC2030
    local WINDOWS_10_DARK_THEME_URL=https://example.invalid/Windows-10-Dark.zip
    validate_config 2>/dev/null
)
expect_failure "Untrusted Windows 10 Dark theme URL is rejected" invalid_theme_url_config

invalid_theme_commit_config() (
    # shellcheck disable=SC2030
    local WINDOWS_10_DARK_THEME_CATALOG_COMMIT=not-a-commit
    validate_config 2>/dev/null
)
expect_failure "Invalid Windows 10 Dark theme catalog commit is rejected" \
    invalid_theme_commit_config

invalid_theme_size_config() (
    # shellcheck disable=SC2030
    local WINDOWS_10_DARK_THEME_SIZE=not-a-size
    validate_config 2>/dev/null
)
expect_failure "Invalid Windows 10 Dark theme archive size is rejected" invalid_theme_size_config

invalid_theme_sha_config() (
    # shellcheck disable=SC2030
    local WINDOWS_10_DARK_THEME_SHA256=0000
    validate_config 2>/dev/null
)
expect_failure "Invalid Windows 10 Dark theme SHA-256 is rejected" invalid_theme_sha_config

alternate_version_config() (
    # shellcheck disable=SC2030
    NAPOS_VERSION=9.8.7
    # shellcheck disable=SC2030
    ISO_VOLUME_ID="NAPOS_${NAPOS_VERSION//./_}"
    validate_config 2>/dev/null
)
expect_success "Configuration supports a version change without duplicated identity" alternate_version_config

# shellcheck disable=SC2031
if [[ "$ISO_VOLUME_ID" == "NAPOS_${NAPOS_VERSION//./_}" ]]; then
    pass "ISO volume ID is derived from the authoritative NapOS version"
else
    fail "ISO volume ID is derived from the authoritative NapOS version"
fi

eval "$(sed -n '/^check_wsl2()/,/^check_native_filesystem()/p' \
    "$PROJECT_ROOT/tools/napos-build" | sed '$d')"

supported_wsl_host_fixture() (
    # shellcheck disable=SC2317
    check_wsl2() { return 0; }
    # shellcheck disable=SC2317
    check_github_actions_ubuntu() { return 1; }
    check_supported_build_host
)
expect_success "Supported-host policy accepts WSL2" supported_wsl_host_fixture

supported_github_host_fixture() (
    # shellcheck disable=SC2317
    check_wsl2() { return 1; }
    # shellcheck disable=SC2317
    check_github_actions_ubuntu() { return 0; }
    check_supported_build_host
)
expect_success "Supported-host policy accepts GitHub-hosted Ubuntu" supported_github_host_fixture

unsupported_host_fixture() (
    # shellcheck disable=SC2317
    check_wsl2() { return 1; }
    # shellcheck disable=SC2317
    check_github_actions_ubuntu() { return 1; }
    check_supported_build_host
)
expect_failure "Supported-host policy rejects other hosts" unsupported_host_fixture

cleanup_outside_github() {
    env -u GITHUB_ACTIONS -u RUNNER_ENVIRONMENT \
        bash "$PROJECT_ROOT/tools/ci/reclaim-github-disk.sh" >/dev/null 2>&1
}
expect_failure "Runner cleanup refuses non-GitHub environments" cleanup_outside_github

cleanup_on_self_hosted_runner() {
    GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=self-hosted \
        bash "$PROJECT_ROOT/tools/ci/reclaim-github-disk.sh" >/dev/null 2>&1
}
expect_failure "Runner cleanup refuses self-hosted environments" cleanup_on_self_hosted_runner

# shellcheck disable=SC2031
if [[ "$MINT_SIGNING_FINGERPRINT" == "27DEB15644C6B3CF3BD7D291300F846BA25BAE09" ]]; then
    pass "Mint signing fingerprint equals the committed pin"
else
    fail "Mint signing fingerprint equals the committed pin"
fi

# shellcheck disable=SC2031
if [[ "$GOOGLE_CHROME_SIGNING_FINGERPRINT" == "EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796" ]]; then
    pass "Google signing fingerprint equals the committed pin"
else
    fail "Google signing fingerprint equals the committed pin"
fi

# shellcheck disable=SC2031
if [[ "$ONLYOFFICE_SIGNING_FINGERPRINT" == "E09CA29F6E178040EF22B4098320CA65CB2DE8E5" ]]; then
    pass "ONLYOFFICE signing fingerprint equals the committed pin"
else
    fail "ONLYOFFICE signing fingerprint equals the committed pin"
fi

# shellcheck disable=SC2031
if [[ "$FCITX5_LOTUS_SIGNING_FINGERPRINT" == "321E097BA44B5A53DB8BA81D55991878A14D5828" ]]; then
    pass "Fcitx5 Lotus signing fingerprint equals the committed pin"
else
    fail "Fcitx5 Lotus signing fingerprint equals the committed pin"
fi

# shellcheck disable=SC2031
if [[ "$WINDOWS_10_DARK_THEME_URL" == \
        "https://cinnamon-spices.linuxmint.com/files/themes/Windows-10-Dark.zip" ]] &&
    [[ "$WINDOWS_10_DARK_THEME_CATALOG_COMMIT" == \
        "deb844046fcf260a85d94c865aa83fd50e5b052b" ]] &&
    [[ "$WINDOWS_10_DARK_THEME_SIZE" == "1165638" ]] &&
    [[ "$WINDOWS_10_DARK_THEME_SHA256" == \
        "5154158e055c035728b90095ff93045b1ed030280d149571c8a765e333d44d35" ]] &&
    [[ "$WINDOWS_10_DARK_THEME_LICENSE" == "GPL-3.0" ]]; then
    pass "Windows 10 Dark theme source equals the reviewed official pin"
else
    fail "Windows 10 Dark theme source equals the reviewed official pin"
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

eval "$(sed -n '/^validate_windows_10_dark_theme_archive()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")"
python3 - "$safe_root/theme-valid.zip" "$safe_root/theme-invalid.zip" <<'PY'
import sys
import zipfile

valid_path, invalid_path = sys.argv[1:]
files = {
    "Windows-10-Dark/LICENSE.md": "GNU GENERAL PUBLIC LICENSE\n",
    "Windows-10-Dark/index.theme": (
        "[Desktop Entry]\nName=Windows-10-Dark\n"
        "[X-GNOME-Metatheme]\nGtkTheme=Windows-10-Dark\n"
    ),
    "Windows-10-Dark/gtk-2.0/gtkrc": "# fixture\n",
    "Windows-10-Dark/gtk-3.0/gtk.css": "/* fixture */\n",
    "Windows-10-Dark/gtk-4.0/gtk.css": "/* fixture */\n",
}
with zipfile.ZipFile(valid_path, "w") as archive:
    for name, content in files.items():
        archive.writestr(name, content)
with zipfile.ZipFile(invalid_path, "w") as archive:
    for name, content in files.items():
        archive.writestr(name, content)
    archive.writestr("outside-theme-root", "invalid\n")
PY

validate_theme_fixture() (
    WINDOWS_10_DARK_THEME_SHA256=$(sha256_of "$1")
    WINDOWS_10_DARK_THEME_SIZE=$(stat -c '%s' "$1")
    validate_windows_10_dark_theme_archive "$1"
)
expect_success "Windows 10 Dark theme archive validator accepts the expected payload" \
    validate_theme_fixture "$safe_root/theme-valid.zip"
expect_failure "Windows 10 Dark theme archive validator rejects files outside its UUID root" \
    validate_theme_fixture "$safe_root/theme-invalid.zip"
expect_failure "Windows 10 Dark theme archive validator rejects a checksum mismatch" \
    validate_windows_10_dark_theme_archive "$safe_root/theme-valid.zip"

printf 'Authenticated Chrome fixture\n' >"$safe_root/chrome.deb"
chrome_fixture_sha=$(sha256_of "$safe_root/chrome.deb")
chrome_fixture_size=$(stat -c '%s' "$safe_root/chrome.deb")
if [[ "${chrome_fixture_sha:0:1}" == 0 ]]; then
    bad_chrome_fixture_sha="1${chrome_fixture_sha:1}"
else
    bad_chrome_fixture_sha="0${chrome_fixture_sha:1}"
fi
expect_success "Chrome cache validator accepts intact size and SHA-256" \
    verify_file_sha256_and_size "$safe_root/chrome.deb" "$chrome_fixture_sha" "$chrome_fixture_size"
expect_failure "Chrome cache validator rejects an incorrect size" \
    verify_file_sha256_and_size "$safe_root/chrome.deb" "$chrome_fixture_sha" "$((chrome_fixture_size + 1))"
expect_failure "Chrome cache validator rejects an incorrect SHA-256" \
    verify_file_sha256_and_size "$safe_root/chrome.deb" "$bad_chrome_fixture_sha" "$chrome_fixture_size"

cat >"$safe_root/InRelease" <<'EOF'
Origin: Google LLC
SHA256:
 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 321 main/binary-amd64/Packages
 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 123 main/binary-amd64/Release
EOF
release_metadata=$(release_file_metadata "$safe_root/InRelease" 'main/binary-amd64/Packages')
if [[ "$release_metadata" == $'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t321' ]]; then
    pass "Signed Release metadata resolves the amd64 Packages index"
else
    fail "Signed Release metadata resolves the amd64 Packages index"
fi
expect_failure "Signed Release metadata rejects a missing index" \
    release_file_metadata "$safe_root/InRelease" 'main/binary-arm64/Packages'

cat >"$safe_root/Packages" <<'EOF'
Package: unrelated-package
Version: 1.0
Architecture: amd64
Filename: pool/main/u/unrelated-package.deb
Size: 10
SHA256: cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc

Package: google-chrome-stable
Version: 151.0.7922.71-1
Architecture: amd64
Filename: pool/main/g/google-chrome-stable/google-chrome-stable_151.0.7922.71-1_amd64.deb
Size: 140000000
SHA256: dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF
package_metadata=$(chrome_package_metadata "$safe_root/Packages")
expected_metadata=$'151.0.7922.71-1\tpool/main/g/google-chrome-stable/google-chrome-stable_151.0.7922.71-1_amd64.deb\tdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\t140000000'
if [[ "$package_metadata" == "$expected_metadata" ]]; then
    pass "Chrome package metadata resolves the stable amd64 package"
else
    fail "Chrome package metadata resolves the stable amd64 package"
fi
sed 's/Architecture: amd64/Architecture: arm64/g' "$safe_root/Packages" >"$safe_root/Packages-wrong-arch"
expect_failure "Chrome package metadata rejects the wrong architecture" \
    chrome_package_metadata "$safe_root/Packages-wrong-arch"
sed 's/Package: google-chrome-stable/Package: google-chrome-beta/' "$safe_root/Packages" >"$safe_root/Packages-wrong-name"
expect_failure "Chrome package metadata rejects the wrong package name" \
    chrome_package_metadata "$safe_root/Packages-wrong-name"
sed 's/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd/not-a-sha256/' \
    "$safe_root/Packages" >"$safe_root/Packages-bad-sha"
expect_failure "Chrome package metadata rejects an invalid package SHA-256" \
    chrome_package_metadata "$safe_root/Packages-bad-sha"

cat >"$safe_root/OnlyOffice-Packages" <<'EOF'
Package: onlyoffice-desktopeditors
Version: 9.3.2-1
Architecture: amd64
Filename: pool/main/o/onlyoffice-desktopeditors/onlyoffice-desktopeditors_9.3.2_amd64.deb
Size: 330000000
SHA256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

Package: unrelated-package
Version: 99.0
Architecture: amd64
Filename: pool/main/u/unrelated-package.deb
Size: 10
SHA256: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

Package: onlyoffice-desktopeditors
Version: 9.4.0-129
Architecture: amd64
Filename: pool/main/o/onlyoffice-desktopeditors/onlyoffice-desktopeditors_9.4.0_amd64.deb
Size: 364644136
SHA256: cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
EOF
onlyoffice_metadata=$(onlyoffice_package_metadata "$safe_root/OnlyOffice-Packages")
expected_onlyoffice_metadata=$'9.4.0-129\tpool/main/o/onlyoffice-desktopeditors/onlyoffice-desktopeditors_9.4.0_amd64.deb\tcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\t364644136'
if [[ "$onlyoffice_metadata" == "$expected_onlyoffice_metadata" ]]; then
    pass "ONLYOFFICE metadata selects the highest stable amd64 version"
else
    fail "ONLYOFFICE metadata selects the highest stable amd64 version"
fi
sed 's/Architecture: amd64/Architecture: arm64/g' "$safe_root/OnlyOffice-Packages" \
    >"$safe_root/OnlyOffice-Packages-wrong-arch"
expect_failure "ONLYOFFICE metadata rejects the wrong architecture" \
    onlyoffice_package_metadata "$safe_root/OnlyOffice-Packages-wrong-arch"
sed 's/Package: onlyoffice-desktopeditors/Package: onlyoffice-desktopeditors-enterprise/g' \
    "$safe_root/OnlyOffice-Packages" >"$safe_root/OnlyOffice-Packages-wrong-name"
expect_failure "ONLYOFFICE metadata rejects the wrong package name" \
    onlyoffice_package_metadata "$safe_root/OnlyOffice-Packages-wrong-name"
sed 's/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/not-a-sha256/' \
    "$safe_root/OnlyOffice-Packages" >"$safe_root/OnlyOffice-Packages-bad-sha"
expect_failure "ONLYOFFICE metadata rejects an invalid package SHA-256" \
    onlyoffice_package_metadata "$safe_root/OnlyOffice-Packages-bad-sha"

cat >"$safe_root/Fcitx5-Lotus-Packages" <<'EOF'
Package: unrelated-package
Version: 99.0
Architecture: amd64
Filename: pool/main/u/unrelated-package.deb
Size: 10
SHA256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

Package: fcitx5-lotus
Version: 3.4.0-1
Architecture: amd64
Filename: pool/main/f/fcitx5-lotus/fcitx5-lotus_3.4.0-1_amd64.deb
Size: 929494
SHA256: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
EOF
lotus_metadata=$(fcitx5_lotus_package_metadata "$safe_root/Fcitx5-Lotus-Packages")
expected_lotus_metadata=$'3.4.0-1\tpool/main/f/fcitx5-lotus/fcitx5-lotus_3.4.0-1_amd64.deb\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t929494'
if [[ "$lotus_metadata" == "$expected_lotus_metadata" ]]; then
    pass "Fcitx5 Lotus metadata resolves the amd64 package"
else
    fail "Fcitx5 Lotus metadata resolves the amd64 package"
fi
sed 's/Architecture: amd64/Architecture: arm64/g' "$safe_root/Fcitx5-Lotus-Packages" \
    >"$safe_root/Fcitx5-Lotus-Packages-wrong-arch"
expect_failure "Fcitx5 Lotus metadata rejects the wrong architecture" \
    fcitx5_lotus_package_metadata "$safe_root/Fcitx5-Lotus-Packages-wrong-arch"
sed 's/Package: fcitx5-lotus/Package: fcitx5-lotus-beta/' "$safe_root/Fcitx5-Lotus-Packages" \
    >"$safe_root/Fcitx5-Lotus-Packages-wrong-name"
expect_failure "Fcitx5 Lotus metadata rejects the wrong package name" \
    fcitx5_lotus_package_metadata "$safe_root/Fcitx5-Lotus-Packages-wrong-name"
sed 's/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/not-a-sha256/' \
    "$safe_root/Fcitx5-Lotus-Packages" >"$safe_root/Fcitx5-Lotus-Packages-bad-sha"
expect_failure "Fcitx5 Lotus metadata rejects an invalid package SHA-256" \
    fcitx5_lotus_package_metadata "$safe_root/Fcitx5-Lotus-Packages-bad-sha"

mkdir -p "$safe_root/onlyoffice-package/DEBIAN" "$safe_root/onlyoffice-package/usr/share/napos-test"
cat >"$safe_root/onlyoffice-package/DEBIAN/control" <<'EOF'
Package: onlyoffice-desktopeditors
Version: 9.4.0-129
Architecture: amd64
Maintainer: NapOS tests <noreply@example.invalid>
Description: ONLYOFFICE validation fixture
EOF
printf 'fixture\n' >"$safe_root/onlyoffice-package/usr/share/napos-test/payload"
dpkg-deb --build "$safe_root/onlyoffice-package" "$safe_root/onlyoffice.deb" >/dev/null
onlyoffice_fixture_sha=$(sha256_of "$safe_root/onlyoffice.deb")
onlyoffice_fixture_size=$(stat -c '%s' "$safe_root/onlyoffice.deb")
expect_success "ONLYOFFICE package validator accepts authenticated metadata" \
    validate_onlyoffice_deb "$safe_root/onlyoffice.deb" 9.4.0-129 \
    "$onlyoffice_fixture_sha" "$onlyoffice_fixture_size"
expect_failure "ONLYOFFICE package validator rejects the wrong version" \
    validate_onlyoffice_deb "$safe_root/onlyoffice.deb" 9.3.2-1 \
    "$onlyoffice_fixture_sha" "$onlyoffice_fixture_size"
expect_failure "ONLYOFFICE package validator rejects the wrong size" \
    validate_onlyoffice_deb "$safe_root/onlyoffice.deb" 9.4.0-129 \
    "$onlyoffice_fixture_sha" "$((onlyoffice_fixture_size + 1))"

mkdir -p "$safe_root/lotus-package/DEBIAN" "$safe_root/lotus-package/usr/share/napos-test"
cat >"$safe_root/lotus-package/DEBIAN/control" <<'EOF'
Package: fcitx5-lotus
Version: 3.4.0-1
Architecture: amd64
Maintainer: NapOS tests <noreply@example.invalid>
Description: Fcitx5 Lotus validation fixture
EOF
printf 'fixture\n' >"$safe_root/lotus-package/usr/share/napos-test/payload"
dpkg-deb --build "$safe_root/lotus-package" "$safe_root/lotus.deb" >/dev/null
lotus_fixture_sha=$(sha256_of "$safe_root/lotus.deb")
lotus_fixture_size=$(stat -c '%s' "$safe_root/lotus.deb")
expect_success "Fcitx5 Lotus package validator accepts authenticated metadata" \
    validate_fcitx5_lotus_deb "$safe_root/lotus.deb" 3.4.0-1 \
    "$lotus_fixture_sha" "$lotus_fixture_size"
expect_failure "Fcitx5 Lotus package validator rejects the wrong version" \
    validate_fcitx5_lotus_deb "$safe_root/lotus.deb" 3.3.1-1 \
    "$lotus_fixture_sha" "$lotus_fixture_size"
expect_failure "Fcitx5 Lotus package validator rejects the wrong size" \
    validate_fcitx5_lotus_deb "$safe_root/lotus.deb" 3.4.0-1 \
    "$lotus_fixture_sha" "$((lotus_fixture_size + 1))"

cat >"$safe_root/google-chrome.sources" <<EOF
Types: deb
URIs: $GOOGLE_CHROME_INSTALLED_APT_URI
Suites: stable
Components: main
Architectures: $GOOGLE_CHROME_ARCH
Signed-By: /usr/share/keyrings/google-chrome.gpg
EOF
expect_success "Google Chrome APT source policy accepts the official source" \
    validate_chrome_apt_source "$safe_root/google-chrome.sources"
sed 's#https://dl.google.com/#https://example.invalid/#' "$safe_root/google-chrome.sources" \
    >"$safe_root/google-chrome-invalid.sources"
expect_failure "Google Chrome APT source policy rejects another origin" \
    validate_chrome_apt_source "$safe_root/google-chrome-invalid.sources"

cat >"$safe_root/fcitx5-lotus.sources" <<EOF
Types: deb
URIs: $FCITX5_LOTUS_APT_ROOT/$UBUNTU_CODENAME
Suites: $UBUNTU_CODENAME
Components: main
Architectures: $FCITX5_LOTUS_ARCH
Signed-By: /usr/share/keyrings/fcitx5-lotus.gpg
EOF
expect_success "Fcitx5 Lotus APT source policy accepts the constrained source" \
    validate_fcitx5_lotus_apt_source "$safe_root/fcitx5-lotus.sources"
sed 's#https://fcitx5-lotus.pages.dev/#https://example.invalid/#' \
    "$safe_root/fcitx5-lotus.sources" >"$safe_root/fcitx5-lotus-invalid.sources"
expect_failure "Fcitx5 Lotus APT source policy rejects another origin" \
    validate_fcitx5_lotus_apt_source "$safe_root/fcitx5-lotus-invalid.sources"
cp "$safe_root/fcitx5-lotus.sources" "$safe_root/fcitx5-lotus-disabled.sources"
printf 'Enabled: no\n' >>"$safe_root/fcitx5-lotus-disabled.sources"
expect_failure "Fcitx5 Lotus APT source policy rejects extra options" \
    validate_fcitx5_lotus_apt_source "$safe_root/fcitx5-lotus-disabled.sources"

conffile_root="$safe_root/conffile-root"
conffile_path=/etc/apt/apt.conf.d/10periodic
mkdir -p "$conffile_root/etc/apt/apt.conf.d" "$conffile_root/var/lib/dpkg"
printf 'APT::Periodic::Update-Package-Lists "1";\n' >"$conffile_root$conffile_path"
conffile_md5=$(md5sum "$conffile_root$conffile_path" | awk '{print $1}')
cat >"$conffile_root/var/lib/dpkg/status" <<EOF
Package: update-notifier-common
Status: install ok installed
Architecture: all
Version: 1
Conffiles:
 $conffile_path $conffile_md5
Description: APT conffile test fixture

EOF
expect_success "Installed package conffile accepts the dpkg-recorded content" \
    verify_installed_conffile "$conffile_root" update-notifier-common "$conffile_path"
printf 'APT::Periodic::Update-Package-Lists "0";\n' >"$conffile_root$conffile_path"
expect_failure "Installed package conffile rejects modified content" \
    verify_installed_conffile "$conffile_root" update-notifier-common "$conffile_path"
expect_failure "Installed package conffile rejects the wrong owning package" \
    verify_installed_conffile "$conffile_root" unexpected-package "$conffile_path"

expected_packages=$'copyq\nfcitx5\nfcitx5-config-qt\nfcitx5-frontend-all\nflameshot\ngtk2-engines-murrine\ngtk2-engines-pixbuf\nttf-mscorefonts-installer\nvlc'
actual_packages=$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PROJECT_ROOT/config/packages.txt" | sort)
if [[ "$actual_packages" == "$expected_packages" ]]; then
    pass "Desktop-essential package profile is exact"
else
    fail "Desktop-essential package profile is exact"
fi

fcitx_profile="$PROJECT_ROOT/config/overlay/etc/skel/.config/fcitx5/profile"
cat >"$safe_root/fcitx5-profile.expected" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=lotus

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=lotus
Layout=

[GroupOrder]
0=Default
EOF
if cmp -s "$fcitx_profile" "$safe_root/fcitx5-profile.expected" &&
    grep -qx 'ActiveByDefault=False' \
        "$PROJECT_ROOT/config/overlay/etc/skel/.config/fcitx5/config" &&
    [[ ! -e "$PROJECT_ROOT/config/overlay/etc/skel/.config/fcitx5/conf/lotus.conf" ]]; then
    pass "Fcitx5 defaults enable Lotus behind the standard Ctrl+Space activation"
else
    fail "Fcitx5 defaults enable Lotus behind the standard Ctrl+Space activation"
fi

lotus_user_helper="$PROJECT_ROOT/config/overlay/usr/libexec/napos-fcitx5-lotus-user"
expect_failure "Lotus user resolver rejects root" bash "$lotus_user_helper" --check root
expect_failure "Lotus user resolver rejects unknown users" \
    bash "$lotus_user_helper" --check napos-user-does-not-exist
mkdir -p "$safe_root/lotus-helper-bin"
cat >"$safe_root/lotus-helper-bin/getent" <<'EOF'
#!/bin/sh
case "$*" in
    'passwd 4242') printf '%s\n' 'live:x:4242:4242:Live user:/home/live:/bin/bash' ;;
    'passwd 120') printf '%s\n' 'lightdm:x:120:120:Display manager:/var/lib/lightdm:/bin/false' ;;
    *) exit 2 ;;
esac
EOF
chmod 0755 "$safe_root/lotus-helper-bin/getent"
expect_success "Lotus user resolver accepts an interactive home user by UID" \
    env PATH="$safe_root/lotus-helper-bin:/usr/bin:/bin" bash "$lotus_user_helper" --check 4242
expect_failure "Lotus user resolver rejects a display-manager account" \
    env PATH="$safe_root/lotus-helper-bin:/usr/bin:/bin" bash "$lotus_user_helper" --check 120

lotus_user_unit="$PROJECT_ROOT/config/overlay/etc/systemd/system/user@.service.d/50-napos-fcitx5-lotus.conf"
lotus_server_unit="$PROJECT_ROOT/config/overlay/etc/systemd/system/fcitx5-lotus-server@.service.d/10-napos-user-resolution.conf"
if grep -Fqx 'Wants=fcitx5-lotus-server@%i.service' "$lotus_user_unit" &&
    grep -Fqx 'PartOf=user@%i.service' "$lotus_server_unit" &&
    grep -Fqx 'ExecCondition=/usr/libexec/napos-fcitx5-lotus-user --check %i' "$lotus_server_unit" &&
    grep -Fqx 'ExecStart=/usr/libexec/napos-fcitx5-lotus-user --exec %i' "$lotus_server_unit"; then
    pass "Lotus server follows each eligible systemd user lifecycle"
else
    fail "Lotus server follows each eligible systemd user lifecycle"
fi

branding_hook="$PROJECT_ROOT/config/hooks/0100-napos-branding.sh"
if grep -Fq 'copyq_desktop=/usr/share/applications/com.github.hluk.copyq.desktop' \
    "$branding_hook" &&
    grep -Fq '/etc/xdg/autostart/com.github.hluk.copyq.desktop' "$branding_hook" &&
    grep -Fq "sed -i 's|^Exec=.*|Exec=copyq|'" "$branding_hook"; then
    pass "CopyQ starts hidden for every desktop login"
else
    fail "CopyQ starts hidden for every desktop login"
fi

if grep -Fq 'flameshot_desktop=/usr/share/applications/org.flameshot.Flameshot.desktop' \
    "$branding_hook" &&
    grep -Fq '/etc/xdg/autostart/org.flameshot.Flameshot.desktop' "$branding_hook" &&
    grep -Fq "sed -i '0,/^Exec=.*/s|^Exec=.*|Exec=flameshot|'" "$branding_hook"; then
    pass "Flameshot starts for every desktop login"
else
    fail "Flameshot starts for every desktop login"
fi

if grep -Fq 'XMODIFIERS=@im=fcitx' "$branding_hook" &&
    grep -Fq 'GTK_IM_MODULE=fcitx' "$branding_hook" &&
    grep -Fq 'QT_IM_MODULE=fcitx' "$branding_hook" &&
    grep -Fq 'SDL_IM_MODULE=fcitx' "$branding_hook" &&
    grep -Fq 'GLFW_IM_MODULE=ibus' "$branding_hook" &&
    grep -Fq '/etc/xdg/autostart/org.fcitx.Fcitx5.desktop' "$branding_hook"; then
    pass "Desktop sessions inherit Fcitx5 variables and global autostart"
else
    fail "Desktop sessions inherit Fcitx5 variables and global autostart"
fi

install_function=$(sed -n '/^install_packages_and_hooks()/,/^}/p' "$PROJECT_ROOT/tools/napos-build")
if grep -Fq '/usr/bin/env LOGNAME=root PATH=/tmp/napos-maintscript-bin:' <<<"$install_function" &&
    grep -Fq 'for command in modprobe udevadm systemctl killall' <<<"$install_function" &&
    grep -Fq '/tmp/napos-fcitx5-lotus.deb' <<<"$install_function" &&
    grep -Fq 'systemd-sysusers' <<<"$install_function"; then
    pass "Lotus package installation isolates maintainer-script host side effects"
else
    fail "Lotus package installation isolates maintainer-script host side effects"
fi

validation_function=$(sed -n '/^validate_customized_rootfs()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")
if grep -Fq 'update-notifier-common:/etc/apt/apt.conf.d/10periodic' \
    <<<"$validation_function" &&
    grep -Fq 'ubuntu-pro-client:/etc/apt/apt.conf.d/20apt-esm-hook.conf' \
    <<<"$validation_function" &&
    grep -Fq 'ubuntu-pro-client:/etc/apt/preferences.d/ubuntu-pro-esm-infra' \
    <<<"$validation_function" &&
    grep -Fq 'verify_installed_conffile' <<<"$validation_function"; then
    pass "Microsoft font dependencies permit only checksum-verified APT conffiles"
else
    fail "Microsoft font dependencies permit only checksum-verified APT conffiles"
fi

build_info_function=$(sed -n '/^write_build_info()/,/^}/p' "$PROJECT_ROOT/tools/napos-build")
verify_function=$(sed -n '/^cmd_verify()/,/^}/p' "$PROJECT_ROOT/tools/napos-build")
if grep -Fq "fcitx5_lotus:{package:\$lotus_package" <<<"$build_info_function" &&
    grep -Fq '.source.fcitx5_lotus.version' <<<"$verify_function" &&
    grep -Fq '.source.fcitx5_lotus.signing_fingerprint' <<<"$verify_function"; then
    pass "Build provenance records and verifies authenticated Fcitx5 Lotus inputs"
else
    fail "Build provenance records and verifies authenticated Fcitx5 Lotus inputs"
fi

# shellcheck disable=SC2016
if grep -Fq 'windows_10_dark_theme:{name:$theme_name' <<<"$build_info_function" &&
    grep -Fq '.source.windows_10_dark_theme.catalog_commit' <<<"$verify_function" &&
    grep -Fq '.source.windows_10_dark_theme.sha256' <<<"$verify_function" &&
    grep -Fq 'fetch_windows_10_dark_theme' "$PROJECT_ROOT/tools/napos-build"; then
    pass "Build fetches, records, and verifies the pinned Windows 10 Dark theme"
else
    fail "Build fetches, records, and verifies the pinned Windows 10 Dark theme"
fi

expected_remove_packages=$(cat <<'EOF'
celluloid
firefox
firefox-locale-de
firefox-locale-en
firefox-locale-es
firefox-locale-fr
firefox-locale-it
firefox-locale-nl
firefox-locale-pt
firefox-locale-ru
fonts-opensymbol
libreoffice-base-core
libreoffice-calc
libreoffice-common
libreoffice-core
libreoffice-draw
libreoffice-gnome
libreoffice-gtk3
libreoffice-help-common
libreoffice-help-de
libreoffice-help-en-gb
libreoffice-help-en-us
libreoffice-help-es
libreoffice-help-fr
libreoffice-help-it
libreoffice-help-nl
libreoffice-help-pt
libreoffice-help-pt-br
libreoffice-help-ru
libreoffice-impress
libreoffice-l10n-de
libreoffice-l10n-en-gb
libreoffice-l10n-en-za
libreoffice-l10n-es
libreoffice-l10n-fr
libreoffice-l10n-it
libreoffice-l10n-nl
libreoffice-l10n-pt
libreoffice-l10n-pt-br
libreoffice-l10n-ru
libreoffice-style-colibre
libreoffice-uiconfig-calc
libreoffice-uiconfig-common
libreoffice-uiconfig-draw
libreoffice-uiconfig-impress
libreoffice-uiconfig-writer
libreoffice-writer
libuno-cppu3t64
libuno-cppuhelpergcc3-3t64
libuno-purpenvhelpergcc3-3t64
libuno-sal3t64
libuno-salhelpergcc3-3t64
mintchat
python3-uno
uno-libs-private
ure
EOF
)
actual_remove_packages=$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' \
    "$PROJECT_ROOT/config/packages-remove.txt" | sort)
if [[ "$actual_remove_packages" == "$expected_remove_packages" ]]; then
    pass "Base-image package removal profile is exact"
else
    fail "Base-image package removal profile is exact"
fi

expected_remove_hash=$(printf '%s\n' "$expected_remove_packages" | sha256sum | awk '{print $1}')
if [[ "$(package_remove_list_hash)" == "$expected_remove_hash" ]]; then
    pass "Package removal profile hash is stable"
else
    fail "Package removal profile hash is stable"
fi

install_function=$(sed -n '/^install_packages_and_hooks()/,/^}/p' "$PROJECT_ROOT/tools/napos-build")
eula_preseed_line=$(grep -n -F -m1 \
    'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula boolean true' \
    <<<"$install_function" | cut -d: -f1 || true)
repository_install_line=$(grep -n -F -m1 'xargs -r apt-get install' \
    <<<"$install_function" | cut -d: -f1 || true)
if [[ -n "$eula_preseed_line" && -n "$repository_install_line" ]] &&
    ((eula_preseed_line < repository_install_line)) &&
    grep -Fq 'debconf-set-selections' <<<"$install_function"; then
    pass "Microsoft core fonts EULA is preseeded before repository package installation"
else
    fail "Microsoft core fonts EULA is preseeded before repository package installation"
fi

branding_hook=$(<"$PROJECT_ROOT/config/hooks/0100-napos-branding.sh")
if grep -Fq 'ubiquity ubiquity/use_nonfree boolean true' <<<"$branding_hook" &&
    grep -Fq 'debconf-set-selections' <<<"$branding_hook"; then
    pass "Live installer enables multimedia codecs by default"
else
    fail "Live installer enables multimedia codecs by default"
fi

if grep -Fq 'napos-packages-remove.txt' <<<"$install_function" &&
    grep -Fq 'apt-get purge -y --' <<<"$install_function"; then
    pass "Build consumes the package removal profile with APT purge"
else
    fail "Build consumes the package removal profile with APT purge"
fi

if grep -Eq 'apt(-get)?[[:space:]]+autoremove' "$PROJECT_ROOT/tools/napos-build"; then
    fail "Package removal policy avoids APT autoremove"
else
    pass "Package removal policy avoids APT autoremove"
fi

if grep -Fq "s/=firefox\\.desktop\$/=google-chrome.desktop/" \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh"; then
    pass "Desktop application defaults replace Firefox with Google Chrome"
else
    fail "Desktop application defaults replace Firefox with Google Chrome"
fi

mimeapps_fixture="$safe_root/mimeapps.list"
cat >"$mimeapps_fixture" <<'EOF'
[Default Applications]
video/mp4=io.github.celluloid_player.Celluloid.desktop
audio/ogg=io.github.celluloid_player.Celluloid.desktop;org.gnome.Rhythmbox3.desktop
audio/flac=org.gnome.Rhythmbox3.desktop
EOF
sed 's/io\.github\.celluloid_player\.Celluloid\.desktop/vlc.desktop/g' "$mimeapps_fixture" \
    >"$safe_root/mimeapps.expected"
if grep -Fq 's/io\.github\.celluloid_player\.Celluloid\.desktop/vlc.desktop/g' \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh" &&
    grep -Fq "grep -Fq \"\$celluloid_desktop\" \"\$mimeapps_file\"" \
        "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh" &&
    grep -qx 'video/mp4=vlc.desktop' "$safe_root/mimeapps.expected" &&
    grep -qx 'audio/ogg=vlc.desktop;org.gnome.Rhythmbox3.desktop' "$safe_root/mimeapps.expected" &&
    grep -qx 'audio/flac=org.gnome.Rhythmbox3.desktop' "$safe_root/mimeapps.expected" &&
    ! grep -Fq 'io.github.celluloid_player.Celluloid.desktop' "$safe_root/mimeapps.expected"; then
    pass "Desktop customization replaces Celluloid defaults with VLC"
else
    fail "Desktop customization replaces Celluloid defaults with VLC"
fi

eval "$(sed -n '/^set_mime_default()/,/^}/p' \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh")"
office_mimeapps_fixture="$safe_root/office-mimeapps.list"
cat >"$office_mimeapps_fixture" <<'EOF'
[Default Applications]
application/pdf=xreader.desktop
application/vnd.oasis.opendocument.text=libreoffice-writer.desktop
application/msword=libreoffice-writer.desktop
application/msword=duplicate.desktop

[Added Associations]
application/msword=libreoffice-writer.desktop;
EOF
set_mime_default "$office_mimeapps_fixture" application/msword onlyoffice-desktopeditors.desktop
set_mime_default "$office_mimeapps_fixture" application/msword onlyoffice-desktopeditors.desktop
set_mime_default "$office_mimeapps_fixture" \
    application/vnd.ms-excel.sheet.macroEnabled.12 onlyoffice-desktopeditors.desktop
default_section=$(awk '
    /^\[Default Applications\]$/ { active=1; next }
    /^\[/ { active=0 }
    active { print }
' "$office_mimeapps_fixture")
if [[ "$(grep -Fc 'application/msword=onlyoffice-desktopeditors.desktop' <<<"$default_section")" == 1 ]] &&
    grep -Fqx 'application/vnd.ms-excel.sheet.macroEnabled.12=onlyoffice-desktopeditors.desktop' \
        <<<"$default_section" &&
    grep -Fqx 'application/pdf=xreader.desktop' <<<"$default_section" &&
    grep -Fqx 'application/vnd.oasis.opendocument.text=libreoffice-writer.desktop' \
        <<<"$default_section" &&
    grep -Fqx 'application/msword=libreoffice-writer.desktop;' "$office_mimeapps_fixture"; then
    pass "ONLYOFFICE MIME defaults replace, insert, deduplicate, and preserve unrelated policy"
else
    fail "ONLYOFFICE MIME defaults replace, insert, deduplicate, and preserve unrelated policy"
fi

if grep -Fq 'application/vnd.ms-excel.sheet.binary.macroEnabled.12' \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh" &&
    grep -Fq 'application/vnd.ms-powerpoint.slideshow.macroEnabled.12' \
        "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh" &&
    grep -Fq 'text/x-comma-separated-values' \
        "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh"; then
    pass "ONLYOFFICE policy includes Microsoft templates, macros, slideshows, RTF, and CSV"
else
    fail "ONLYOFFICE policy includes Microsoft templates, macros, slideshows, RTF, and CSV"
fi

eval "$(sed -n '/^validate_cinnamon_panel_defaults()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")"
eval "$(sed -n '/^validate_cinnamon_desktop_defaults()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")"
eval "$(sed -n '/^validate_cinnamon_launcher_defaults()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")"
eval "$(sed -n '/^validate_desktop_shortcuts()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")"
eval "$(sed -n '/^validate_cinnamon_copyq_defaults()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")"
eval "$(sed -n '/^validate_cinnamon_theme_defaults()/,/^}/p' \
    "$PROJECT_ROOT/tools/napos-build")"
dconf_defaults=$(awk '
    index($0, "cat >/etc/dconf/db/local.d/00-napos") { active=1; next }
    active && $0 == "EOF" { exit }
    active { print }
' "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh")
expect_success "Cinnamon defaults center the menu and grouped application list" \
    validate_cinnamon_panel_defaults "$dconf_defaults"
left_panel_defaults=$(sed \
    -e 's/panel1:center:0:menu@cinnamon.org/panel1:left:0:menu@cinnamon.org/' \
    -e 's/panel1:center:1:grouped-window-list@cinnamon.org/panel1:left:2:grouped-window-list@cinnamon.org/' \
    <<<"$dconf_defaults")
expect_failure "Cinnamon defaults reject the original left-side applet positions" \
    validate_cinnamon_panel_defaults "$left_panel_defaults"
incomplete_panel_defaults=${dconf_defaults/panel1:right:8:sound@cinnamon.org/panel1:right:8:missing@cinnamon.org}
expect_failure "Cinnamon defaults require every preserved Mint status applet" \
    validate_cinnamon_panel_defaults "$incomplete_panel_defaults"
expect_success "Cinnamon defaults enable Computer, Home, Trash, and mounted drives" \
    validate_cinnamon_desktop_defaults "$dconf_defaults"
missing_desktop_icon=${dconf_defaults/home-icon-visible=true/home-icon-visible=false}
expect_failure "Cinnamon defaults reject a disabled desktop icon" \
    validate_cinnamon_desktop_defaults "$missing_desktop_icon"
expect_success "Cinnamon defaults bind Super+V to the CopyQ history toggle" \
    validate_cinnamon_copyq_defaults "$dconf_defaults"
invalid_copyq_defaults=${dconf_defaults//<Super>v/<Super>x}
expect_failure "Cinnamon CopyQ defaults reject an incorrect shortcut" \
    validate_cinnamon_copyq_defaults "$invalid_copyq_defaults"
expect_success "Cinnamon defaults select Windows-10-Dark, the Yaru pointer, and dark mode" \
    validate_cinnamon_theme_defaults "$dconf_defaults"
wrong_application_theme=${dconf_defaults/gtk-theme=\'Windows-10-Dark\'/gtk-theme=\'Mint-Y-Aqua\'}
expect_failure "Cinnamon defaults reject the wrong Applications theme" \
    validate_cinnamon_theme_defaults "$wrong_application_theme"
icon_theme_defaults=${dconf_defaults/gtk-theme=\'Windows-10-Dark\'/$'gtk-theme=\'Windows-10-Dark\'\nicon-theme=\'Windows-10-Icons\''}
expect_failure "Cinnamon theme defaults reject an accompanying icon change" \
    validate_cinnamon_theme_defaults "$icon_theme_defaults"
wrong_cursor_theme=${dconf_defaults/cursor-theme=\'Yaru\'/cursor-theme=\'DMZ-White\'}
expect_failure "Cinnamon theme defaults reject the wrong mouse pointer" \
    validate_cinnamon_theme_defaults "$wrong_cursor_theme"
wrong_color_scheme=${dconf_defaults/color-scheme=\'prefer-dark\'/color-scheme=\'prefer-light\'}
expect_failure "Cinnamon theme defaults reject a non-dark color scheme" \
    validate_cinnamon_theme_defaults "$wrong_color_scheme"
desktop_theme_defaults=$dconf_defaults$'\n[org/cinnamon/theme]\nname=\'Windows-10-Dark\''
expect_failure "Cinnamon theme defaults reject an accompanying desktop-theme change" \
    validate_cinnamon_theme_defaults "$desktop_theme_defaults"
window_theme_defaults=$dconf_defaults$'\n[org/cinnamon/desktop/wm/preferences]\ntheme=\'Windows-10-Dark\''
expect_failure "Cinnamon theme defaults reject an accompanying window-border change" \
    validate_cinnamon_theme_defaults "$window_theme_defaults"

grouped_launcher_fixture="$safe_root/grouped-window-list.json"
panel_launcher_fixture="$safe_root/panel-launchers.json"
taskbar_launchers=()
eval "$(sed -n '/^taskbar_launchers=(/,/^)/p' \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh")"
if [[ "${taskbar_launchers[*]}" == \
    "nemo.desktop google-chrome.desktop onlyoffice-desktopeditors.desktop mintinstall.desktop cinnamon-settings.desktop org.gnome.SystemMonitor.desktop" ]]; then
    pass "Branding hook defines the requested taskbar launcher order"
else
    fail "Branding hook defines the requested taskbar launcher order"
fi
cat >"$grouped_launcher_fixture" <<'EOF'
{"pinned-apps":{"default":["nemo.desktop","google-chrome.desktop","onlyoffice-desktopeditors.desktop","mintinstall.desktop","cinnamon-settings.desktop","org.gnome.SystemMonitor.desktop"]}}
EOF
cat >"$panel_launcher_fixture" <<'EOF'
{"launcherList":{"default":["nemo.desktop","google-chrome.desktop","onlyoffice-desktopeditors.desktop","mintinstall.desktop","cinnamon-settings.desktop","org.gnome.SystemMonitor.desktop"]}}
EOF
expect_success "Cinnamon taskbar defaults preserve the requested launcher order" \
    validate_cinnamon_launcher_defaults "$(cat "$grouped_launcher_fixture")" \
    "$(cat "$panel_launcher_fixture")"
reordered_grouped=$(sed \
    's/"nemo.desktop","google-chrome.desktop"/"google-chrome.desktop","nemo.desktop"/' \
    "$grouped_launcher_fixture")
expect_failure "Cinnamon taskbar defaults reject reordered launchers" \
    validate_cinnamon_launcher_defaults "$reordered_grouped" \
    "$(cat "$panel_launcher_fixture")"
incomplete_panel_launchers=$(sed 's/,"org.gnome.SystemMonitor.desktop"//' \
    "$panel_launcher_fixture")
expect_failure "Cinnamon taskbar defaults require every requested launcher" \
    validate_cinnamon_launcher_defaults "$(cat "$grouped_launcher_fixture")" \
    "$incomplete_panel_launchers"

eval "$(sed -n '/^install_desktop_shortcuts()/,/^}/p' \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh")"
desktop_shortcuts=()
eval "$(sed -n '/^desktop_shortcuts=(/,/^)/p' \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh")"
if [[ "${desktop_shortcuts[*]}" == \
    "google-chrome.desktop onlyoffice-desktopeditors.desktop mintinstall.desktop org.gnome.SystemMonitor.desktop" ]]; then
    pass "Branding hook defines the requested desktop shortcuts"
else
    fail "Branding hook defines the requested desktop shortcuts"
fi
shortcut_sources="$safe_root/shortcut-sources"
shortcut_desktop="$safe_root/shortcut-desktop"
mkdir -p "$shortcut_sources"
desktop_shortcut_names=(
    google-chrome.desktop
    onlyoffice-desktopeditors.desktop
    mintinstall.desktop
    org.gnome.SystemMonitor.desktop
)
for desktop_shortcut in "${desktop_shortcut_names[@]}"; do
    printf '[Desktop Entry]\nName=%s\n' "$desktop_shortcut" \
        >"$shortcut_sources/$desktop_shortcut"
done
expect_success "Desktop shortcut installer copies every requested application" \
    install_desktop_shortcuts "$shortcut_sources" "$shortcut_desktop" \
    "${desktop_shortcut_names[@]}"
expect_success "Default desktop shortcuts are executable and match their sources" \
    validate_desktop_shortcuts "$shortcut_desktop" "$shortcut_sources"
touch "$shortcut_desktop/ubiquity.desktop"
expect_failure "Default desktop shortcuts exclude the live installer" \
    validate_desktop_shortcuts "$shortcut_desktop" "$shortcut_sources"
rm -f -- "$shortcut_desktop/ubiquity.desktop" "$shortcut_sources/mintinstall.desktop"
expect_failure "Desktop shortcut installation rejects a missing application source" \
    install_desktop_shortcuts "$shortcut_sources" "$shortcut_desktop" mintinstall.desktop

if ! rg -n '/org/cinnamon/desktop/interface/(gtk|cursor)-theme|/org/x/apps/portal/color-scheme' \
    "$PROJECT_ROOT/config" >/dev/null; then
    pass "Cinnamon theme defaults are not locked"
else
    fail "Cinnamon theme defaults are not locked"
fi

if ! rg -n '/org/nemo/desktop/(computer-icon-visible|home-icon-visible|trash-icon-visible|volumes-visible)' \
    "$PROJECT_ROOT/config" >/dev/null; then
    pass "Cinnamon desktop icon defaults are not locked"
else
    fail "Cinnamon desktop icon defaults are not locked"
fi

if rg -n 'Napos' "$PROJECT_ROOT/remix.conf" "$PROJECT_ROOT/config" >/dev/null; then
    fail 'Incorrect product spelling "Napos" exists in configuration or assets'
else
    pass "Branding capitalization is exact"
fi

wallpaper="$PROJECT_ROOT/config/overlay/usr/share/backgrounds/napos/napos-wallpaper.svg"
if [[ -s "$wallpaper" ]] &&
    grep -Fq '<svg xmlns="http://www.w3.org/2000/svg"' "$wallpaper" &&
    grep -Fq 'width="3840" height="2160"' "$wallpaper"; then
    pass "Wallpaper is a non-empty 4K SVG asset"
else
    fail "Wallpaper is a non-empty 4K SVG asset"
fi

if rg -n --fixed-strings '0.1.0' "$PROJECT_ROOT/tools/napos-build" >/dev/null; then
    fail "Build implementation avoids a hard-coded NapOS release version"
else
    pass "Build implementation avoids a hard-coded NapOS release version"
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

github_prepare=$(sed -n '/^prepare_github_work_tree()/,/^}/p' "$PROJECT_ROOT/tools/napos-build")
# shellcheck disable=SC2016
if grep -Fq 'xorriso -osirrox on -indev "$base_iso" -extract / "$ISO_TREE"' \
    <<<"$github_prepare" &&
    grep -Fq 'sudo unsquashfs -no-progress -d "$ROOTFS"' <<<"$github_prepare" &&
    ! grep -Fq 'BASE_CACHE_DIR' <<<"$github_prepare" &&
    ! grep -Fq 'rsync' <<<"$github_prepare"; then
    pass "GitHub preparation avoids a duplicate expanded base cache"
else
    fail "GitHub preparation avoids a duplicate expanded base cache"
fi

ci_workflow="$PROJECT_ROOT/.github/workflows/ci.yml"
release_workflow="$PROJECT_ROOT/.github/workflows/release.yml"
if grep -Fq 'pull_request:' "$ci_workflow" && grep -Fq 'push:' "$ci_workflow" &&
    grep -Fq 'run: make test' "$ci_workflow"; then
    pass "CI workflow tests pull requests and main pushes"
else
    fail "CI workflow tests pull requests and main pushes"
fi

if grep -Fq 'workflow_dispatch:' "$release_workflow" &&
    ! grep -Fq 'pull_request:' "$release_workflow" && ! grep -Fq 'push:' "$release_workflow" &&
    grep -Fq 'refs/heads/main' "$release_workflow" &&
    grep -Fq 'run: make release' "$release_workflow"; then
    pass "Release workflow is manual, main-only, and uses the release build"
else
    fail "Release workflow is manual, main-only, and uses the release build"
fi

# shellcheck disable=SC2016
if grep -Fq 'compression-level: 0' "$release_workflow" &&
    grep -Fq 'retention-days: 1' "$release_workflow" &&
    grep -Fq 'cache/downloads/${{ steps.build-config.outputs.base_sha256 }}' "$release_workflow" &&
    grep -Fq 'cache/gnupg' "$release_workflow" &&
    ! grep -Eq 'uses: [^ ]+@v[0-9]' "$ci_workflow" "$release_workflow"; then
    pass "Release artifact and cache policies are bounded and actions are SHA-pinned"
else
    fail "Release artifact and cache policies are bounded and actions are SHA-pinned"
fi

if (( failures > 0 )); then
    printf '\n%d self-test(s) failed.\n' "$failures" >&2
    exit 1
fi
printf '\nAll NapOS non-networked tests passed.\n'
