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
[org/cinnamon]
enabled-applets=['panel1:center:0:menu@cinnamon.org', 'panel1:left:1:separator@cinnamon.org', 'panel1:center:1:grouped-window-list@cinnamon.org', 'panel1:right:0:systray@cinnamon.org', 'panel1:right:1:xapp-status@cinnamon.org', 'panel1:right:2:notifications@cinnamon.org', 'panel1:right:3:printers@cinnamon.org', 'panel1:right:4:removable-drives@cinnamon.org', 'panel1:right:5:keyboard@cinnamon.org', 'panel1:right:6:favorites@cinnamon.org', 'panel1:right:7:network@cinnamon.org', 'panel1:right:8:sound@cinnamon.org', 'panel1:right:9:power@cinnamon.org', 'panel1:right:10:calendar@cinnamon.org', 'panel1:right:11:cornerbar@cinnamon.org']

[org/cinnamon/desktop/background]
picture-uri='file:///usr/share/backgrounds/napos/napos-wallpaper.svg'
picture-options='zoom'

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/napos/napos-wallpaper.svg'
picture-options='zoom'
EOF
dconf update

printf '[NapOS] Configuring Fcitx5 Lotus defaults...\n'
chmod 0755 /usr/libexec/napos-fcitx5-lotus-user
for variable in XMODIFIERS GTK_IM_MODULE QT_IM_MODULE SDL_IM_MODULE GLFW_IM_MODULE; do
    sed -i "/^${variable}=/d" /etc/environment
done
cat >>/etc/environment <<'EOF'
XMODIFIERS=@im=fcitx
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
EOF

fcitx_desktop=/usr/share/applications/org.fcitx.Fcitx5.desktop
[[ -f "$fcitx_desktop" ]] || {
    printf 'Required Fcitx5 desktop launcher is missing: %s\n' "$fcitx_desktop" >&2
    exit 1
}
mkdir -p /etc/xdg/autostart /etc/apt/sources.list.d /usr/share/keyrings
cp "$fcitx_desktop" /etc/xdg/autostart/org.fcitx.Fcitx5.desktop
chmod 0644 /etc/xdg/autostart/org.fcitx.Fcitx5.desktop

[[ -s /usr/share/keyrings/fcitx5-lotus.gpg ]] || {
    printf 'Authenticated Fcitx5 Lotus keyring is missing.\n' >&2
    exit 1
}
cat >/etc/apt/sources.list.d/fcitx5-lotus.sources <<EOF
Types: deb
URIs: https://fcitx5-lotus.pages.dev/apt/$UBUNTU_CODENAME
Suites: $UBUNTU_CODENAME
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/fcitx5-lotus.gpg
EOF

rm -f /etc/systemd/system/multi-user.target.wants/fcitx5-lotus-server@root.service
systemd-sysusers

printf '[NapOS] Configuring default applications...\n'
celluloid_desktop=io.github.celluloid_player.Celluloid.desktop
vlc_desktop=vlc.desktop
onlyoffice_desktop=onlyoffice-desktopeditors.desktop
[[ -f "/usr/share/applications/$vlc_desktop" ]] || {
    printf 'Required VLC desktop launcher is missing: %s\n' "/usr/share/applications/$vlc_desktop" >&2
    exit 1
}
[[ -f "/usr/share/applications/$onlyoffice_desktop" ]] || {
    printf 'Required ONLYOFFICE desktop launcher is missing: %s\n' \
        "/usr/share/applications/$onlyoffice_desktop" >&2
    exit 1
}

set_mime_default() {
    local mimeapps_file=$1
    local mime_type=$2
    local desktop=$3
    local temporary
    temporary=$(mktemp)
    awk -v wanted="$mime_type" -v desktop="$desktop" '
        BEGIN { in_defaults=0; found_defaults=0; written=0 }
        /^\[Default Applications\]$/ {
            if (in_defaults && !written) {
                print wanted "=" desktop
                written=1
            }
            in_defaults=1
            found_defaults=1
            print
            next
        }
        /^\[/ {
            if (in_defaults && !written) {
                print wanted "=" desktop
                written=1
            }
            in_defaults=0
            print
            next
        }
        in_defaults && index($0, wanted "=") == 1 {
            if (!written) {
                print wanted "=" desktop
                written=1
            }
            next
        }
        { print }
        END {
            if (in_defaults && !written) {
                print wanted "=" desktop
            } else if (!found_defaults) {
                if (NR > 0) print ""
                print "[Default Applications]"
                print wanted "=" desktop
            }
        }
    ' "$mimeapps_file" >"$temporary"
    cat "$temporary" >"$mimeapps_file"
    rm -f -- "$temporary"
}

office_mime_types=(
    application/msword
    application/msword-template
    application/vnd.ms-word.document.macroEnabled.12
    application/vnd.ms-word.template.macroEnabled.12
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.wordprocessingml.template
    application/vnd.ms-excel
    application/vnd.ms-excel.sheet.macroEnabled.12
    application/vnd.ms-excel.sheet.binary.macroEnabled.12
    application/vnd.ms-excel.template.macroEnabled.12
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.openxmlformats-officedocument.spreadsheetml.template
    application/vnd.ms-powerpoint
    application/vnd.ms-powerpoint.presentation.macroEnabled.12
    application/vnd.ms-powerpoint.slideshow.macroEnabled.12
    application/vnd.ms-powerpoint.template.macroEnabled.12
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/vnd.openxmlformats-officedocument.presentationml.slideshow
    application/vnd.openxmlformats-officedocument.presentationml.template
    application/rtf
    text/rtf
    application/csv
    text/csv
    text/comma-separated-values
    text/x-comma-separated-values
)
onlyoffice_launcher="/usr/share/applications/$onlyoffice_desktop"
for mime_type in "${office_mime_types[@]}"; do
    mime_list=$(grep -m1 '^MimeType=' "$onlyoffice_launcher")
    if [[ ";${mime_list#MimeType=}" != *";$mime_type;"* ]]; then
        sed -i "s#^MimeType=#MimeType=$mime_type;#" "$onlyoffice_launcher"
    fi
done
mimeapps_files=(
    /usr/share/applications/mimeapps.list
    /usr/share/ubuntu-system-adjustments/mimeapps.list
)
for mimeapps_file in "${mimeapps_files[@]}"; do
    [[ -f "$mimeapps_file" ]] || {
        printf 'Required MIME application policy is missing: %s\n' "$mimeapps_file" >&2
        exit 1
    }
    sed -i \
        -e 's/=firefox\.desktop$/=google-chrome.desktop/' \
        -e 's/io\.github\.celluloid_player\.Celluloid\.desktop/vlc.desktop/g' \
        "$mimeapps_file"
    for mime_type in "${office_mime_types[@]}"; do
        set_mime_default "$mimeapps_file" "$mime_type" "$onlyoffice_desktop"
    done
    if grep -Fq "$celluloid_desktop" "$mimeapps_file"; then
        printf 'Celluloid remains assigned in MIME application policy: %s\n' "$mimeapps_file" >&2
        exit 1
    fi
    for mime_type in "${office_mime_types[@]}"; do
        grep -Fqx "$mime_type=$onlyoffice_desktop" "$mimeapps_file" || {
            printf 'ONLYOFFICE is not the default for %s in %s\n' "$mime_type" "$mimeapps_file" >&2
            exit 1
        }
    done
done

launcher_schemas=(
    /usr/share/cinnamon/applets/grouped-window-list@cinnamon.org/settings-schema.json
    /usr/share/cinnamon/applets/panel-launchers@cinnamon.org/settings-schema.json
)
for launcher_schema in "${launcher_schemas[@]}"; do
    [[ -f "$launcher_schema" ]] || {
        printf 'Required Cinnamon launcher schema is missing: %s\n' "$launcher_schema" >&2
        exit 1
    }
    sed -i 's/firefox\.desktop/google-chrome.desktop/g' "$launcher_schema"
done

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
