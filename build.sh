#!/usr/bin/env bash
# Builds the Ubuntu 24.04 + niri + Noctalia live/installer ISO inside a privileged Docker container.
#
#   ./build.sh [all|packages|rootfs|iso|shell|clean]
#
# all       packages, rootfs and iso (default)
# packages  niri, xwayland-satellite, Noctalia and Noctalia Greeter as .deb in $WORKDIR/debs
# rootfs    debootstrap chroot in $WORKDIR/chroot with the packages and the configuration
# iso       squashfs, GRUB (UEFI with shim + BIOS) and the hybrid ISO in $WORKDIR/out
# shell     interactive shell in the builder container
# clean     removes chroot, ISO tree and output (keeps sources, cache and .deb)
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.env
source "$repo/config.env"
# shellcheck disable=SC1091
[[ -f "$repo/config.local.env" ]] && source "$repo/config.local.env"

stage="${1:-all}"
case "$stage" in
  all|packages|rootfs|iso|shell|clean) ;;
  *) echo "usage: $0 [all|packages|rootfs|iso|shell|clean]" >&2; exit 2 ;;
esac

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
mkdir -p "$WORKDIR"

image="nirintu-builder:latest"
docker build -q --build-arg RUST_TOOLCHAIN="$RUST_TOOLCHAIN" -t "$image" "$repo/docker" >/dev/null

tty_flags=(-i)
[[ -t 0 && -t 1 ]] && tty_flags=(-it)

# --privileged: debootstrap creates device nodes and the chroot needs proc, sys and dev mounts.
exec docker run --rm "${tty_flags[@]}" --privileged \
  --name "nirintu-$stage-$$" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$repo:/src:ro" \
  -v "$WORKDIR:/work" \
  "$image" /src/scripts/run.sh "$stage"
