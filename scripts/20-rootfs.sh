#!/usr/bin/env bash
# Stage 2: debootstrap chroot with the desktop, the local packages and the live/installer setup.
# The chroot is always rebuilt from scratch.
set -euo pipefail
source /src/scripts/lib.sh

compgen -G "$DEBS/*.deb" >/dev/null || die "no packages in $DEBS: run the packages stage first"

trap 'umount_chroot "$CHROOT"' EXIT
umount_chroot "$CHROOT"
rm -rf "$CHROOT"

log "debootstrap $SUITE"
debootstrap --variant=minbase --components=main,restricted,universe,multiverse \
  --include=ca-certificates,gnupg "$SUITE" "$CHROOT" "$MIRROR"
mount_chroot "$CHROOT"

# Services must not start inside the chroot.
printf '#!/bin/sh\nexit 101\n' > "$CHROOT/usr/sbin/policy-rc.d"
chmod 755 "$CHROOT/usr/sbin/policy-rc.d"
# Name resolution during the build (systemd-resolved later replaces this file with a link).
rm -f "$CHROOT/etc/resolv.conf"
cp /etc/resolv.conf "$CHROOT/etc/resolv.conf"

log "apt sources"
rm -f "$CHROOT/etc/apt/sources.list"
cat > "$CHROOT/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: $SUITE $SUITE-updates $SUITE-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $SECURITY_MIRROR
Suites: $SUITE-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
tar -C /src/rootfs/pre --owner=0 --group=0 -cf - . | tar -C "$CHROOT" -xf -
install -d -m 755 "$CHROOT/etc/apt/keyrings"
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  -o "$CHROOT/etc/apt/keyrings/packages.mozilla.org.asc"
# apt in the chroot: no recommends unless listed.
cat > "$CHROOT/etc/apt/apt.conf.d/90-nirintu" <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

# Answers for packages that ask during installation.
in_chroot debconf-set-selections <<EOF
keyboard-configuration keyboard-configuration/layoutcode string $LIVE_KEYMAP
keyboard-configuration keyboard-configuration/xkb-keymap select $LIVE_KEYMAP
EOF

log "packages"
mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' /src/packages.list | grep -v '^$')
pkgs+=("linux-$KERNEL_FLAVOUR")
if [[ -n "$NVIDIA_DRIVER" ]]; then
  pkgs+=("nvidia-driver-$NVIDIA_DRIVER" "linux-modules-nvidia-$NVIDIA_DRIVER-$KERNEL_FLAVOUR")
fi
for lang in $LANGUAGE_PACKS; do
  pkgs+=("language-pack-$lang" "language-pack-gnome-$lang")
done
# shellcheck disable=SC2206
pkgs+=($EXTRA_PACKAGES)
in_chroot apt-get update
in_chroot apt-get -y full-upgrade
in_chroot apt-get install -y "${pkgs[@]}"

log "local packages"
mkdir -p "$CHROOT/tmp/debs"
cp "$DEBS"/*.deb "$CHROOT/tmp/debs/"
in_chroot sh -c 'apt-get install -y /tmp/debs/*.deb'
rm -rf "$CHROOT/tmp/debs"
cp "$DEBS/SOURCES" "$CHROOT/usr/share/doc/nirintu-sources.txt"

in_chroot dpkg -l snapd 2>/dev/null | grep -q '^ii' && die "snapd ended up in the image"

log "configuration"
tar -C /src/rootfs/post --owner=0 --group=0 -cf - . | tar -C "$CHROOT" -xf -
mkdir -p "$CHROOT/etc/calamares"
tar -C /src/calamares --owner=0 --group=0 -cf - . | tar -C "$CHROOT/etc/calamares" -xf -
# Installer launcher icon: the branding logo.
install -Dm644 /src/calamares/branding/nirintu/logo.png "$CHROOT/usr/share/icons/hicolor/256x256/apps/nirintu.png"
in_chroot gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
chmod 600 "$CHROOT/etc/netplan/01-network-manager-all.yaml"

# BIOS installs swap grub-efi-amd64 for grub-pc from this pool (see bios-grub).
mkdir -p "$CHROOT/usr/share/nirintu/pool"
# grub-pc and the dependencies the image lacks (grub-gfxpayload-lists); checked after cleanup.
in_chroot sh -c 'cd /usr/share/nirintu/pool && apt-get download grub-pc grub-gfxpayload-lists'

# Locale, keyboard, time zone and host name of the live session.
echo "LANG=$LIVE_LOCALE" > "$CHROOT/etc/default/locale"
sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$LIVE_KEYMAP\"/" "$CHROOT/etc/default/keyboard"
ln -sf "/usr/share/zoneinfo/$LIVE_TIMEZONE" "$CHROOT/etc/localtime"
echo "$LIVE_TIMEZONE" > "$CHROOT/etc/timezone"
echo "$LIVE_HOSTNAME" > "$CHROOT/etc/hostname"
cat > "$CHROOT/etc/casper.conf" <<EOF
export USERNAME="$LIVE_USER"
export USERFULLNAME="Live session user"
export HOST="$LIVE_HOSTNAME"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="$DISTRO_NAME"
EOF

# greetd: live session logs in once automatically; installed system shows only the greeter.
greeter=/opt/noctalia-greeter/bin/noctalia-greeter-session
[[ -x "$CHROOT$greeter" ]] || die "missing $greeter"
cat > "$CHROOT/usr/share/nirintu/greetd-installed.toml" <<EOF
[terminal]
vt = 7

[default_session]
command = "$greeter"
user = "_greetd"
EOF
{
  cat "$CHROOT/usr/share/nirintu/greetd-installed.toml"
  printf '\n[initial_session]\ncommand = "niri-session"\nuser = "%s"\n' "$LIVE_USER"
} > "$CHROOT/etc/greetd/config.toml"
in_chroot systemctl enable greetd.service NetworkManager.service systemd-resolved.service
in_chroot systemctl set-default graphical.target

# niri: default configuration with Noctalia in place of waybar, fuzzel and swaylock.
niri_cfg="$CHROOT/etc/skel/.config/niri/config.kdl"
mkdir -p "$(dirname "$niri_cfg")"
cp "$CHROOT/usr/share/niri/default-config.kdl" "$niri_cfg"
patch_niri() { # pattern replacement
  grep -qF -- "$1" "$niri_cfg" || die "niri default config: '$1' not found"
  local esc_p esc_r
  esc_p=$(printf '%s' "$1" | sed 's/[][\.*^$/|]/\\&/g')
  esc_r=$(printf '%s' "$2" | sed 's/[\&/|]/\\&/g')
  sed -i "s|$esc_p|$esc_r|" "$niri_cfg"
}
patch_niri 'spawn-at-startup "waybar"' 'spawn-at-startup "noctalia" "--daemon"'
patch_niri 'hotkey-overlay-title="Run an Application: fuzzel" { spawn "fuzzel"; }' \
  'hotkey-overlay-title="Run an Application: Noctalia launcher" { spawn-sh "noctalia msg panel-toggle launcher"; }'
patch_niri 'hotkey-overlay-title="Lock the Screen: swaylock" { spawn "swaylock"; }' \
  'hotkey-overlay-title="Lock the Screen: Noctalia" { spawn-sh "noctalia msg session lock"; }'

# Live session: casper builds the live user's home from /etc/skel before greetd starts, so
# gnome-keyring-daemon (started by pam_gnome_keyring) finds an unencrypted, empty-password login
# keyring. Without it, the autologin has no password to create one and the first secret request
# opens a "new keyring password" dialog. finish-install removes it from the installed system.
keyrings="$CHROOT/etc/skel/.local/share/keyrings"
mkdir -p "$keyrings"
chmod 700 "$keyrings"
printf '[keyring]\ndisplay-name=Login\nctime=0\nmtime=0\nlock-on-idle=false\nlock-after=false\n' \
  > "$keyrings/login.keyring"
printf 'login' > "$keyrings/default"
chmod 600 "$keyrings/login.keyring" "$keyrings/default"

# Noctalia: Polkit agent on, kabronius plugin sources next to the official ones.
mkdir -p "$CHROOT/etc/skel/.config/noctalia"
cat > "$CHROOT/etc/skel/.config/noctalia/config.toml" <<EOF
[shell]
polkit_agent = true

[plugins]
enabled = [
    "kabronius/variety",
    "kabronius/greeter-settings"
]

[[plugins.source]]
kind = "git"
location = "https://github.com/noctalia-dev/official-plugins"
name = "official"

[[plugins.source]]
kind = "git"
location = "https://github.com/noctalia-dev/community-plugins"
name = "community"

[[plugins.source]]
kind = "git"
location = "$GREETER_PLUGIN_REPO"
name = "kabronius-greeter"

[[plugins.source]]
kind = "git"
location = "$VARIETY_PLUGIN_REPO"
name = "kabronius-variety"
EOF

# Icon theme: gsettings default (read by GTK 4 and Noctalia) and GTK settings.ini.
printf "[org.gnome.desktop.interface]\nicon-theme='%s'\n" "$ICON_THEME" \
  > "$CHROOT/usr/share/glib-2.0/schemas/90_nirintu.gschema.override"
in_chroot glib-compile-schemas /usr/share/glib-2.0/schemas
for v in 3.0 4.0; do
  mkdir -p "$CHROOT/etc/gtk-$v"
  printf '[Settings]\ngtk-icon-theme-name=%s\n' "$ICON_THEME" > "$CHROOT/etc/gtk-$v/settings.ini"
done
[[ -d "$CHROOT/usr/share/icons/$ICON_THEME" ]] || die "icon theme $ICON_THEME not installed"

# GRUB themes, installed on the target by nirintu-grub-theme (Calamares grub_theme step).
if [[ -n "$GRUB_THEMES" ]]; then
  log "grub themes"
  themes="$CHROOT/usr/share/nirintu/grub-themes"
  mkdir -p "$themes"
  for t in $GRUB_THEMES; do
    curl -fsSL -o "$themes/$t.tar" "$GRUB_THEMES_REPO/$GRUB_THEMES_COMMIT/themes/$t.tar"
    [[ "$(tar -tf "$themes/$t.tar")" =~ (^|$'\n')(\./)?theme\.txt($|$'\n') ]] \
      || die "GRUB theme $t: no theme.txt"
  done
  curl -fsSL -o "$themes/LICENSE" "$GRUB_THEMES_REPO/$GRUB_THEMES_COMMIT/LICENSE"
  echo "$GRUB_THEME_FALLBACK" > "$themes/FALLBACK"
fi

log "flathub"
in_chroot flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

log "initramfs"
in_chroot update-initramfs -u -k all

log "cleanup"
rm -f "$CHROOT/usr/sbin/policy-rc.d"
in_chroot apt-get clean
rm -rf "$CHROOT"/var/lib/apt/lists/* "$CHROOT"/tmp/* "$CHROOT"/var/tmp/* "$CHROOT"/root/.cache
# Without package lists, as in the offline installer: the BIOS swap (bios-grub) must resolve from
# the installed packages and the pool alone.
in_chroot sh -c 'dpkg --simulate -i /usr/share/nirintu/pool/*.deb' >/dev/null \
  || die "grub-pc pool incomplete: dpkg --simulate fails without package lists"
: > "$CHROOT/etc/machine-id"
rm -f "$CHROOT/var/lib/dbus/machine-id"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$CHROOT/etc/resolv.conf"
find "$CHROOT/var/log" -type f -exec truncate -s 0 {} +

umount_chroot "$CHROOT"
log "rootfs ready in $CHROOT"
