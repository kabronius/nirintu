# Contributing to Nirintu

Changes are tested by building the ISO and booting it in a virtual machine; the full technical reference is
[docs/BUILDING.md](docs/BUILDING.md).

## Repository layout

| Path | Content |
| --- | --- |
| `build.sh` | entry point on the host: builds the Docker builder image and runs a stage in it |
| `config.env` | versions, component refs, live session settings, image options |
| `packages.list` | packages installed in the image |
| `docker/Dockerfile` | builder image (Ubuntu 24.04 with the build dependencies and rustup) |
| `scripts/10-packages.sh` | stage 1: niri, xwayland-satellite, Noctalia and Noctalia Greeter as `.deb` |
| `scripts/20-rootfs.sh` | stage 2: debootstrap chroot, packages, configuration of the live and installed system |
| `scripts/30-iso.sh` | stage 3: squashfs, GRUB for UEFI and BIOS, hybrid ISO |
| `rootfs/pre`, `rootfs/post` | files copied into the image before and after the package installation |
| `calamares/` | installer configuration and branding |
| `.github/workflows/release.yml` | release build on tags |

## Making a change

1. Edit the files; component versions and image options live in `config.env`, local overrides in
   `config.local.env` (not tracked).
2. Build: `./build.sh` for everything, or `./build.sh rootfs` and `./build.sh iso` when the four source
   packages are unchanged.
3. Boot the ISO in QEMU with `virtio-vga-gl` (see [Testing in QEMU](docs/BUILDING.md#testing-in-qemu)); for
   installer changes, run a full installation on an empty virtual disk, on UEFI and on BIOS.
4. Shell scripts should pass `shellcheck -x`.

## Updating components

| Change | Where |
| --- | --- |
| niri or xwayland-satellite release | `NIRI_REF`, `XWS_REF` in `config.env` |
| Noctalia or greeter branch | `NOCTALIA_REF`, `GREETER_REF` (the branches carry the noble port; see their READMEs for rebasing) |
| NVIDIA branch, none | `NVIDIA_DRIVER` (`""` for Mesa only) |
| Additional packages | `packages.list` or `EXTRA_PACKAGES` |
| Languages | `LANGUAGE_PACKS` |
| Icon theme | `ICON_THEME` (any theme installed by `packages.list`) |
| GRUB themes | `GRUB_THEMES`, `GRUB_THEMES_COMMIT`, `GRUB_THEME_FALLBACK` (`GRUB_THEMES=""` for the text menu) |
| Live language and layout | `LIVE_LOCALE`, `LIVE_KEYMAP`, `LIVE_TIMEZONE` |

## Commits

- English, subject in the imperative mood and under about 70 characters ("Add …", "Fix …").
- The body explains why the change is needed and anything not obvious from the diff.
- One logical change per commit.

## Releases

Versions are `<Ubuntu base>.<Nirintu release>`: 24.04.1, 24.04.2 and so on on Ubuntu 24.04.

1. Set `NIRINTU_VERSION` in `config.env`.
2. Add a `## <version>` section to [CHANGELOG.md](CHANGELOG.md).
3. Optionally run the **Release** workflow by hand (`workflow_dispatch`) to check the build on GitHub.
4. Tag and push: `git tag -a v<version> -m "Nirintu <version>"` and `git push origin v<version>`.

The workflow checks the tag against `config.env` and the changelog, builds the ISO from scratch and publishes
the release with the package manifest and the component commits. Details in
[docs/BUILDING.md](docs/BUILDING.md#releases).
