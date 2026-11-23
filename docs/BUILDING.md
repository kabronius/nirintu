# Building Nirintu

Technical reference for the build: what goes into the image, how each stage works, how the live session
and the installer are put together. The [README](../README.md) is the overview; [CONTRIBUTING](../CONTRIBUTING.md)
covers changes and releases.

## Contents of the image

| Area | Content |
| --- | --- |
| Base | debootstrap `minbase` + `ubuntu-minimal`, kernel `linux-generic-hwe-24.04`, no recommends unless listed |
| Snap | `snapd` pinned to priority -10: never installed, not even as a dependency |
| Graphics | Mesa, `nvidia-driver-580` with Canonical-signed prebuilt modules (`linux-modules-nvidia-580-generic-hwe-24.04`, valid with Secure Boot) |
| Session | niri, xwayland-satellite, Noctalia (`--daemon` from niri), xdg-desktop-portal-gnome/gtk, gnome-keyring, PipeWire |
| Translations | `language-pack-*` and `language-pack-gnome-*` for `LANGUAGE_PACKS` (default `en it`), included because the installer is offline |
| Icons | Papirus (`ICON_THEME`, default `Papirus-Dark`) as gsettings default and in `/etc/gtk-{3,4}.0/settings.ini`; Noctalia reads the same gsettings key |
| GRUB | theme from [distro-grub-themes](https://github.com/AdisonCavani/distro-grub-themes) chosen by vendor and model at install time (`nirintu-grub-theme`) |
| Login | greetd on VT 7 with Noctalia Greeter (`_greetd`); in the live session one autologin through `initial_session` |
| Applications | Alacritty, Nautilus, Firefox from the Mozilla APT repository, Flatpak with Flathub, Variety |
| Noctalia plugins | `kabronius/greeter-settings` and `kabronius/variety` as git sources, enabled for new users |
| Installer | Calamares 3.3 (Qt5, native Wayland via `qtwayland5`), offline, Nirintu branding (see below) |
| Dual boot | `GRUB_DISABLE_OS_PROBER=false` (`/etc/default/grub.d/70-nirintu-os-prober.cfg`): other installed systems are added to the GRUB menu |

The full package list is in [packages.list](../packages.list); the source commits of the four locally built
packages are in `/usr/share/doc/nirintu-sources.txt` inside the image.

## Build

Requirements on the host: Docker (user in the `docker` group), network access, about 25 GB free in
`WORKDIR` (default `/var/tmp/nirintu`). No `sudo` is needed on the host: every stage runs in a
privileged `ubuntu:24.04` container built from [docker/Dockerfile](../docker/Dockerfile).

```sh
./build.sh            # packages + rootfs + iso
./build.sh packages   # only the .deb
./build.sh rootfs     # only the chroot (needs the .deb)
./build.sh iso        # only the ISO (needs the chroot)
./build.sh shell      # shell in the builder container, /work = WORKDIR
./build.sh clean      # removes chroot, ISO tree and output; keeps sources, cargo cache and .deb
```

Output: `$WORKDIR/out/nirintu-<NIRINTU_VERSION>-amd64.iso` with `.sha256` and the package manifest.
Settings are in [config.env](../config.env); local overrides go in `config.local.env` (ignored by git).

### Stage 1: packages

| Package | Source | Build |
| --- | --- | --- |
| `niri` | `NIRI_REPO` @ `NIRI_REF` | `cargo build --release --locked` with rustup (`RUST_TOOLCHAIN`; noble's rustc 1.75 is below niri's 1.87 minimum); session files, systemd user units and `default-config.kdl` in `/usr/share/niri` |
| `xwayland-satellite` | `XWS_REPO` @ `XWS_REF` | `cargo build --release --locked` |
| `noctalia` | `NOCTALIA_REPO` @ `NOCTALIA_REF` (`ubuntu-24.04`) | `dpkg-buildpackage` with the branch's `debian/` |
| `noctalia-greeter` | `GREETER_REPO` @ `GREETER_REF` | `packaging/ubuntu-24.04/build.sh` + `make-deb.sh` (private wlroots 0.20 stack in `/opt/noctalia-greeter`) |

`niri` and `xwayland-satellite` get their `Depends` from `dpkg-shlibdeps`. A package is rebuilt only when the
commit of its checkout changes (`$WORKDIR/debs/<name>.commit`); the cargo registry is cached in
`$WORKDIR/cache/cargo`.

### Stage 2: rootfs

The chroot is rebuilt from scratch at every run:

1. `debootstrap --variant=minbase` with main, restricted, universe and multiverse; sources in deb822 format
   (`-updates`, `-backports`, `-security`).
2. [rootfs/pre](../rootfs/pre) before any installation: snapd pin, Mozilla repository and its pin over Ubuntu's
   snap-wrapper `firefox`.
3. `full-upgrade`, then [packages.list](../packages.list) + kernel + NVIDIA + `EXTRA_PACKAGES`, then the local
   `.deb`. The stage fails if `snapd` is installed.
4. [rootfs/post](../rootfs/post) and [calamares](../calamares) into `/etc/calamares`, after the packages so that no
   conffile prompt occurs.
5. Live session settings (`LIVE_*`), `casper.conf`, greetd, `/etc/skel` for niri and Noctalia, Flathub,
   `update-initramfs` with the casper hooks, cleanup (`machine-id` empty, apt lists and logs removed).

The niri configuration in `/etc/skel` is niri's own default with three substitutions: `noctalia --daemon`
instead of waybar, the Noctalia launcher instead of fuzzel, the Noctalia lock instead of swaylock. The stage
fails if one of the original lines is missing, so that a new niri default does not silently lose them. The
keyboard layout is not set in niri: niri reads it from `systemd-localed`, which the installer configures.

### Stage 3: ISO

| Element | Content |
| --- | --- |
| `casper/` | `vmlinuz`, `initrd`, `filesystem.squashfs` (zstd 19, 1 MiB blocks), `.manifest`, `.size` |
| UEFI | El Torito alternate entry on GPT partition 2 (FAT, 10 MiB): `bootx64.efi` = shim, `grubx64.efi` = Canonical-signed `gcdx64`, `mmx64.efi`; taken from the image, so Secure Boot works |
| BIOS | `eltorito.img` from `grub-mkimage -O i386-pc-eltorito`, modules in `boot/grub/i386-pc` |
| Hybrid | `boot_hybrid.img` MBR, `-partition_offset 16`: the same file boots from optical media and from USB (`dd`) |

The signed GRUB finds the medium through `/.disk/info` and reads `/boot/grub/grub.cfg`. Boot entries: normal
and `nomodeset`, plus UEFI firmware settings.

## Live session and installer

At boot casper creates `LIVE_USER` with passwordless sudo; greetd starts `niri-session` for that user once
(`initial_session`), then shows the greeter on logout. `/etc/skel/.local/share/keyrings` holds an unencrypted,
empty-password `login` keyring that casper copies into the live home before greetd starts: without a password
`pam_gnome_keyring` cannot create one, and the first secret request would open a "new keyring password" dialog.
`finish-install` removes it from the installed system. The launcher shipped by the `calamares` package is hidden by a
`NoDisplay` copy in `/usr/local/share/applications`. On the installed system the keyring is
created and unlocked by `pam_gnome_keyring` with the login password (noble's `/etc/pam.d/greetd` already includes it). The installer is **Install Nirintu** in the Noctalia
launcher (`nirintu-installer`: Calamares as root on the user's Wayland socket).

Calamares sequence ([calamares/settings.conf](../calamares/settings.conf)), derived from
`calamares-settings-lubuntu` 24.04:

| Step | Notes |
| --- | --- |
| `partition` | ext4 default, btrfs and xfs available, LUKS2 automatic partitioning (separate unencrypted `/boot` of 2 GiB), swap file |
| `unpackfs` | `/cdrom/casper/filesystem.squashfs` |
| `packages` | removes `calamares` and `casper`; no `apt-get update`, the installation works offline |
| `initramfs` | regenerated without the casper hooks |
| `contextualprocess@bios_grub` | BIOS only: replaces `grub-efi-amd64` with `grub-pc` from `/usr/share/nirintu/pool`, `grub-pc/install_devices` preseeded with the disk holding `/boot` (through partitions, LUKS and LVM) |
| `shellprocess@grub_theme` | `nirintu-grub-theme auto --no-update`: GRUB theme for the detected machine (see below) |
| `bootloader` | GRUB; on UEFI shim + signed GRUB, `ubuntu` boot entry and fallback `EFI/BOOT/BOOTX64.EFI` |
| `shellprocess@finish` | greetd without `initial_session`; installer launchers, live keyring in `/etc/skel` and `/etc/calamares` removed |
| `shellprocess@logs` | Calamares and casper logs in `/var/log/installer` |

## Installer branding

[calamares/branding/nirintu](../calamares/branding/nirintu) uses Noctalia's default palette:

| Role | Colour |
| --- | --- |
| Background, sidebar | `#070722` |
| Page surface | `#11112d` |
| Controls | `#24234b`, outline `#3a3970` |
| Primary action (Next/Install), current sidebar step, progress | `#fff59b` |
| Selection, slideshow keys | `#a9aefe` |
| Text | `#e6e6f8` |

| File | Content |
| --- | --- |
| `branding.desc` | names, URLs, sidebar colours, 1000×640 window |
| `stylesheet.qss` | dark Qt stylesheet for pages, buttons, fields, lists and progress bar |
| `show.qml` | slideshow during installation (welcome, niri, Noctalia, applications, boot), Italian or English from the locale |
| `logo.png` 256², `icon.png` 128², `welcome.png` 640×300 | placeholder logo; the final logo replaces them with the same names and sizes; `logo.png` is also the launcher icon `nirintu` |

## GRUB theme

`GRUB_THEMES` lists the themes of [distro-grub-themes](https://github.com/AdisonCavani/distro-grub-themes) (pinned to
`GRUB_THEMES_COMMIT`) copied as `.tar` into `/usr/share/nirintu/grub-themes`, about 0.4 MB each. During installation
`nirintu-grub-theme` reads `/sys/class/dmi/id` and picks the theme:

| DMI `sys_vendor` (`board_vendor` when the former is a placeholder) | Model match (`product_name`, `product_version`, `product_family`, `board_name`) | Theme |
| --- | --- | --- |
| Lenovo | ThinkPad / Legion / other | `thinkpad` / `legion` / `lenovo` |
| ASUS | ROG / TUF / other | `asus-rog` / `asus-tuf` / `asus` |
| HP, Hewlett-Packard | OMEN / Victus / other | `hp-omen` / `hp-victus` / `hp` |
| Gigabyte | AORUS / other | `aorus` / `gigabyte` |
| Framework | Laptop 13 / other | `framework13` / `framework` |
| Dell, Alienware | | `dell` |
| Acer, MSI, ASRock, Razer, System76, Samsung, Huawei, LG, Toshiba/Dynabook, Fujitsu, Medion, Sony/VAIO, Supermicro, Apple | | theme of the same name |
| anything else, or theme not shipped | | `GRUB_THEME_FALLBACK` (`ubuntu`) |

The theme is extracted into `/boot/grub/themes/<name>` (on the unencrypted `/boot` when the root is LUKS) and
`/etc/default/grub.d/90-nirintu-theme.cfg` sets `GRUB_THEME`, `GRUB_GFXMODE=auto`, `GRUB_TIMEOUT_STYLE=menu` and
`GRUB_TIMEOUT=5` (Ubuntu hides the menu and boots immediately by default). Ubuntu's signed GRUB has `gfxmenu`, `gfxterm` and the PNG/JPEG readers built in,
so themes work with Secure Boot. After installation:

```sh
nirintu-grub-theme list            # available themes, * = detected
nirintu-grub-theme detect          # DMI strings and detected theme
sudo nirintu-grub-theme thinkpad   # set a theme and run update-grub
sudo nirintu-grub-theme auto       # back to the detected one
sudo nirintu-grub-theme none       # text menu
```

## Releases

Versions are `<Ubuntu base>.<Nirintu release>` (`NIRINTU_VERSION` in `config.env`, history in
[CHANGELOG.md](../CHANGELOG.md)). Pushing the tag `v$NIRINTU_VERSION` runs
[.github/workflows/release.yml](../.github/workflows/release.yml) on a GitHub-hosted runner:

1. the tag must match `NIRINTU_VERSION` and `CHANGELOG.md` must have a section for it;
2. `./build.sh all` builds the ISO from scratch in `/mnt` (the runner's larger disk);
3. a GitHub release is created with the CHANGELOG section as notes and two files: the package manifest of the
   image and the commits of niri, xwayland-satellite, Noctalia and Noctalia Greeter.

The ISO is not attached: GitHub limits release files to 2 GiB and the image is about 2.5 GB. The same workflow can
be started by hand (`workflow_dispatch`) to check the build without publishing. Inside the image
`/etc/nirintu-release` records the version, the commit of this repository and the build date.

## Testing in QEMU

```sh
iso=/var/tmp/nirintu/out/nirintu-*-amd64.iso
qemu-img create -f qcow2 /var/tmp/nirintu-test.qcow2 30G
# UEFI (OVMF from the ovmf package)
qemu-system-x86_64 -enable-kvm -m 6G -smp 4 -cpu host \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=/var/tmp/nirintu-vars.fd \
  -device virtio-vga-gl -display gtk,gl=on \
  -drive file=/var/tmp/nirintu-test.qcow2,if=virtio -cdrom $iso
```

`/var/tmp/nirintu-vars.fd` is a copy of `/usr/share/OVMF/OVMF_VARS_4M.fd`. niri needs a GPU with
OpenGL ES; without `virtio-vga-gl` it falls back to software rendering (pixman) and is slow.
