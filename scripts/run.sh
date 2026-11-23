#!/usr/bin/env bash
# Entry point inside the builder container.
set -euo pipefail

source /src/scripts/lib.sh

case "${1:-all}" in
  packages) /src/scripts/10-packages.sh ;;
  rootfs)   /src/scripts/20-rootfs.sh ;;
  iso)      /src/scripts/30-iso.sh ;;
  all)
    /src/scripts/10-packages.sh
    /src/scripts/20-rootfs.sh
    /src/scripts/30-iso.sh
    ;;
  shell) exec bash ;;
  clean)
    umount_chroot "$CHROOT"
    rm -rf "$CHROOT" "$ISO_TREE" "$OUT"
    log "removed chroot, ISO tree and output"
    ;;
esac
