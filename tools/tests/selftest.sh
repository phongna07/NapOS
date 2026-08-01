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
    find "$PROJECT_ROOT/tools" "$PROJECT_ROOT/config/hooks" -type f \
        \( -name '*.sh' -o -path "$PROJECT_ROOT/tools/napos-build" \) | sort
)
for script in "${scripts[@]}"; do
    expect_success "Bash syntax: ${script#"$PROJECT_ROOT/"}" bash -n "$script"
done

if shellcheck -x "$PROJECT_ROOT/tools/napos-build" "$PROJECT_ROOT/tools/lib/common.sh" \
    "$PROJECT_ROOT/tools/tests/selftest.sh" "$PROJECT_ROOT/tools/ci/reclaim-github-disk.sh" \
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh"; then
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

expected_packages=$'curl\nflameshot\ngit\nhtop\nvim\nvlc'
actual_packages=$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PROJECT_ROOT/config/packages.txt" | sort)
if [[ "$actual_packages" == "$expected_packages" ]]; then
    pass "Desktop-essential package profile is exact"
else
    fail "Desktop-essential package profile is exact"
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
    "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh" &&
    grep -Fq "s/firefox\\.desktop/google-chrome.desktop/g" \
        "$PROJECT_ROOT/config/hooks/0100-napos-branding.sh"; then
    pass "Desktop customization replaces Firefox defaults with Google Chrome"
else
    fail "Desktop customization replaces Firefox defaults with Google Chrome"
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
