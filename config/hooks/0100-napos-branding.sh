#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -Eeuo pipefail

required=(NAPOS_NAME NAPOS_ID NAPOS_VERSION NAPOS_EDITION BASE_VERSION BASE_CODENAME UBUNTU_CODENAME DEFAULT_LOCALE DEFAULT_TIMEZONE BUILD_PROFILE BUILD_ID BUILD_TIMESTAMP)
for variable in "${required[@]}"; do
    [[ -n "${!variable:-}" ]] || {
        printf 'Missing hook environment variable: %s\n' "$variable" >&2
        exit 1
    }
done

[[ "$NAPOS_NAME" == "NapOS" ]] || {
    printf 'Product display name must be exactly NapOS.\n' >&2
    exit 1
}

printf '[NapOS] Configuring locale and timezone...\n'
if grep -q '^# en_US.UTF-8 UTF-8' /etc/locale.gen; then
    sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
fi
locale-gen en_US.UTF-8
cat >/etc/default/locale <<EOF
LANG=$DEFAULT_LOCALE
LANGUAGE=en_US:en
EOF
ln -snf "/usr/share/zoneinfo/$DEFAULT_TIMEZONE" /etc/localtime
printf '%s\n' "$DEFAULT_TIMEZONE" >/etc/timezone

printf '[NapOS] Writing conservative operating-system identity...\n'
cat >/usr/lib/os-release <<EOF
NAME="NapOS"
PRETTY_NAME="NapOS $NAPOS_VERSION"
ID=linuxmint
ID_LIKE="ubuntu debian"
VERSION_ID="$BASE_VERSION"
VERSION="$NAPOS_VERSION (based on Linux Mint $BASE_VERSION)"
VERSION_CODENAME=$BASE_CODENAME
UBUNTU_CODENAME=$UBUNTU_CODENAME
VARIANT="NapOS"
VARIANT_ID=$NAPOS_ID
EOF
ln -snf ../usr/lib/os-release /etc/os-release

cat >/etc/napos-release <<EOF
NAPOS_NAME="NapOS"
NAPOS_ID="$NAPOS_ID"
NAPOS_VERSION="$NAPOS_VERSION"
NAPOS_EDITION="$NAPOS_EDITION"
NAPOS_BUILD_PROFILE="$BUILD_PROFILE"
NAPOS_BUILD_ID="$BUILD_ID"
NAPOS_BUILD_TIMESTAMP="$BUILD_TIMESTAMP"
NAPOS_BASE_NAME="Linux Mint"
NAPOS_BASE_VERSION="$BASE_VERSION"
NAPOS_BASE_CODENAME="$BASE_CODENAME"
NAPOS_UBUNTU_CODENAME="$UBUNTU_CODENAME"
EOF
printf 'NapOS %s \\n \\l\n' "$NAPOS_VERSION" >/etc/issue
printf 'NapOS %s\n' "$NAPOS_VERSION" >/etc/issue.net

printf '[NapOS] Installing Cinnamon desktop defaults...\n'
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
cat >/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
cat >/etc/dconf/db/local.d/00-napos <<'EOF'
[org/cinnamon/desktop/background]
picture-uri='file:///usr/share/backgrounds/napos/napos-wallpaper.svg'
picture-options='zoom'

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/napos/napos-wallpaper.svg'
picture-options='zoom'
EOF
dconf update

printf '[NapOS] Branding the installer launcher...\n'
installer_found=0
for desktop in \
    /usr/share/applications/ubiquity.desktop \
    /usr/share/applications/live-installer.desktop \
    /usr/share/applications/calamares.desktop; do
    [[ -f "$desktop" ]] || continue
    installer_found=1
    temporary=$(mktemp)
    awk '
        /^Name(\[[^]]+\])?=/ { next }
        /^Icon=/ { next }
        { print }
        END {
            print "Name=Install NapOS"
            print "Name[vi]=Cài đặt NapOS"
            print "Icon=napos-logo"
        }
    ' "$desktop" >"$temporary"
    cat "$temporary" >"$desktop"
    rm -f "$temporary"
done
(( installer_found == 1 )) || {
    printf 'No supported Mint installer desktop launcher was found.\n' >&2
    exit 1
}

if [[ -f /usr/share/applications/ubiquity.desktop ]]; then
    mkdir -p /etc/skel/Desktop
    cp /usr/share/applications/ubiquity.desktop /etc/skel/Desktop/ubiquity.desktop
    chmod 0755 /etc/skel/Desktop/ubiquity.desktop
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor || true
fi

printf '[NapOS] Branding complete.\n'
