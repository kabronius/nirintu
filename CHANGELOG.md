# Changelog

Versions follow `<Ubuntu base>.<Nirintu release>`: 24.04.1 is the first release on Ubuntu 24.04 LTS.

## 24.04.1

First release.

### Image

- Ubuntu 24.04 LTS (noble) with the HWE kernel, without snap: `snapd` is pinned away and Firefox comes from
  the Mozilla APT repository.
- niri 26.04 and xwayland-satellite 0.8.3, built from source.
- Noctalia 5.0.1 and Noctalia Greeter 1.7.0 from the Ubuntu 24.04 ports (kabronius), with per-output modes in
  the greeter.
- NVIDIA driver 580 with Canonical-signed prebuilt modules (Secure Boot), Mesa for the other GPUs.
- PipeWire, NetworkManager, Bluetooth, Flatpak with Flathub, Alacritty, Nautilus, Variety, Papirus icons,
  Italian and English language packs.
- Noctalia preconfigured with the Polkit agent and the `kabronius/greeter-settings` and `kabronius/variety`
  plugin sources.

### Live session and installer

- Hybrid ISO booting on UEFI (shim and Canonical-signed GRUB, Secure Boot) and BIOS, from optical media or USB.
- Live session with automatic login through greetd.
- Offline Calamares installer with Nirintu branding: LUKS2 automatic partitioning, swap file, removal of the
  live packages, grub-pc on BIOS machines.
- GRUB theme chosen from the machine's vendor and model (`nirintu-grub-theme`), menu shown for 5 seconds,
  os-prober enabled for dual boot.

### Known limitations

- The ISO is not attached to the release: it is built with `./build.sh` (see the README).
- The logo is a placeholder.
