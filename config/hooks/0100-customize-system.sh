#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

set -Eeuo pipefail

required=(UBUNTU_CODENAME DEFAULT_LOCALE DEFAULT_TIMEZONE)
for variable in "${required[@]}"; do
    [[ -n "${!variable:-}" ]] || {
        printf 'Missing hook environment variable: %s\n' "$variable" >&2
        exit 1
    }
done

printf '[vnmint] Configuring installer defaults...\n'
printf '%s\n' 'ubiquity ubiquity/use_nonfree boolean true' |
    debconf-set-selections

printf '[vnmint] Configuring locale and timezone...\n'
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

printf '[vnmint] Installing Cinnamon desktop defaults...\n'
mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
cat >/etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
cat >/etc/dconf/db/local.d/00-desktop-defaults <<'EOF'
[org/cinnamon]
enabled-applets=['panel1:center:0:menu@cinnamon.org', 'panel1:left:1:separator@cinnamon.org', 'panel1:center:1:grouped-window-list@cinnamon.org', 'panel1:right:0:systray@cinnamon.org', 'panel1:right:1:xapp-status@cinnamon.org', 'panel1:right:2:notifications@cinnamon.org', 'panel1:right:3:printers@cinnamon.org', 'panel1:right:4:removable-drives@cinnamon.org', 'panel1:right:5:keyboard@cinnamon.org', 'panel1:right:6:favorites@cinnamon.org', 'panel1:right:7:network@cinnamon.org', 'panel1:right:8:sound@cinnamon.org', 'panel1:right:9:power@cinnamon.org', 'panel1:right:10:calendar@cinnamon.org', 'panel1:right:11:cornerbar@cinnamon.org']

[org/cinnamon/desktop/interface]
gtk-theme='Windows-10-Dark'
cursor-theme='Yaru'

[org/nemo/desktop]
computer-icon-visible=true
home-icon-visible=true
trash-icon-visible=true
volumes-visible=true

[org/x/apps/portal]
color-scheme='prefer-dark'

[org/cinnamon/desktop/keybindings]
custom-list=['custom0']

[org/cinnamon/desktop/keybindings/custom-keybindings/custom0]
name='CopyQ Clipboard History'
binding=['<Super>v']
command='copyq toggle'

EOF
dconf update

printf '[vnmint] Configuring CopyQ clipboard history...\n'
copyq_desktop=/usr/share/applications/com.github.hluk.copyq.desktop
[[ -f "$copyq_desktop" ]] || {
    printf 'Required CopyQ desktop launcher is missing: %s\n' "$copyq_desktop" >&2
    exit 1
}
mkdir -p /etc/xdg/autostart
cp "$copyq_desktop" /etc/xdg/autostart/com.github.hluk.copyq.desktop
sed -i 's|^Exec=.*|Exec=copyq|' /etc/xdg/autostart/com.github.hluk.copyq.desktop
grep -qx 'Exec=copyq' /etc/xdg/autostart/com.github.hluk.copyq.desktop || {
    printf 'Failed to configure hidden CopyQ autostart.\n' >&2
    exit 1
}
chmod 0644 /etc/xdg/autostart/com.github.hluk.copyq.desktop

printf '[vnmint] Configuring Flameshot screenshot tool...\n'
flameshot_desktop=/usr/share/applications/org.flameshot.Flameshot.desktop
[[ -f "$flameshot_desktop" ]] || {
    printf 'Required Flameshot desktop launcher is missing: %s\n' "$flameshot_desktop" >&2
    exit 1
}
mkdir -p /etc/xdg/autostart
cp "$flameshot_desktop" /etc/xdg/autostart/org.flameshot.Flameshot.desktop
sed -i '0,/^Exec=.*/s|^Exec=.*|Exec=flameshot|' \
    /etc/xdg/autostart/org.flameshot.Flameshot.desktop
grep -qx 'Exec=flameshot' /etc/xdg/autostart/org.flameshot.Flameshot.desktop || {
    printf 'Failed to configure Flameshot autostart.\n' >&2
    exit 1
}
chmod 0644 /etc/xdg/autostart/org.flameshot.Flameshot.desktop

printf '[vnmint] Configuring Fcitx5 Lotus defaults...\n'
chmod 0755 /usr/libexec/fcitx5-lotus-user-resolver
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

printf '[vnmint] Configuring default applications...\n'
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

set_cinnamon_launcher_defaults() {
    local schema=$1
    local setting=$2
    local temporary
    shift 2
    temporary=$(mktemp)
    python3 - "$schema" "$setting" "$@" >"$temporary" <<'PY'
import json
import sys

schema_path = sys.argv[1]
setting_name = sys.argv[2]
launchers = sys.argv[3:]

with open(schema_path, encoding="utf-8") as schema_file:
    schema = json.load(schema_file)

if setting_name not in schema or "default" not in schema[setting_name]:
    raise SystemExit(f"Cinnamon launcher setting is missing: {setting_name}")

schema[setting_name]["default"] = launchers
json.dump(schema, sys.stdout, indent=4, ensure_ascii=False)
sys.stdout.write("\n")
PY
    cat "$temporary" >"$schema"
    rm -f -- "$temporary"
}

taskbar_launchers=(
    nemo.desktop
    google-chrome.desktop
    onlyoffice-desktopeditors.desktop
    mintinstall.desktop
    cinnamon-settings.desktop
    org.gnome.SystemMonitor.desktop
)
for launcher in "${taskbar_launchers[@]}"; do
    [[ -f "/usr/share/applications/$launcher" ]] || {
        printf 'Required taskbar launcher is missing: %s\n' "/usr/share/applications/$launcher" >&2
        exit 1
    }
done
grouped_window_schema=/usr/share/cinnamon/applets/grouped-window-list@cinnamon.org/settings-schema.json
panel_launchers_schema=/usr/share/cinnamon/applets/panel-launchers@cinnamon.org/settings-schema.json
for launcher_schema in "$grouped_window_schema" "$panel_launchers_schema"; do
    [[ -f "$launcher_schema" ]] || {
        printf 'Required Cinnamon launcher schema is missing: %s\n' "$launcher_schema" >&2
        exit 1
    }
done
set_cinnamon_launcher_defaults "$grouped_window_schema" pinned-apps "${taskbar_launchers[@]}"
set_cinnamon_launcher_defaults "$panel_launchers_schema" launcherList "${taskbar_launchers[@]}"

install_desktop_shortcuts() {
    local application_dir=$1
    local desktop_dir=$2
    local launcher
    shift 2
    mkdir -p "$desktop_dir"
    for launcher in "$@"; do
        [[ -f "$application_dir/$launcher" ]] || {
            printf 'Required desktop shortcut source is missing: %s\n' \
                "$application_dir/$launcher" >&2
            return 1
        }
        install -m 0755 "$application_dir/$launcher" "$desktop_dir/$launcher"
    done
}

desktop_shortcuts=(
    google-chrome.desktop
    onlyoffice-desktopeditors.desktop
    mintinstall.desktop
    org.gnome.SystemMonitor.desktop
)
install_desktop_shortcuts /usr/share/applications /etc/skel/Desktop \
    "${desktop_shortcuts[@]}"
for installer_shortcut in ubiquity.desktop live-installer.desktop calamares.desktop; do
    rm -f -- "/etc/skel/Desktop/$installer_shortcut"
done

printf '[vnmint] Rebuilding the initramfs with Linux Mint Plymouth defaults...\n'
update-initramfs -u -k all
initrd_listing=$(lsinitramfs /boot/initrd.img)
grep -Fq 'mint-logo' <<<"$initrd_listing" || {
    printf 'Rebuilt initramfs does not contain the Linux Mint Plymouth theme.\n' >&2
    exit 1
}

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor || true
fi

printf '[vnmint] Customization complete.\n'
