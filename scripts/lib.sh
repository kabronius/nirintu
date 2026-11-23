# Shared settings and helpers for the in-container stages.
# shellcheck shell=bash

# shellcheck source=../config.env
source /src/config.env
# shellcheck disable=SC1091
[[ -f /src/config.local.env ]] && source /src/config.local.env

export DEBIAN_FRONTEND=noninteractive
export CARGO_HOME=/work/cache/cargo

SRC_DIR=/work/src
DEBS=/work/debs
CHROOT=/work/chroot
ISO_TREE=/work/iso
OUT=/work/out

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Shallow checkout of a branch or tag; reuses an existing clone.
checkout() { # url ref dest
  local url=$1 ref=$2 dest=$3
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" remote set-url origin "$url"
    git -C "$dest" fetch -q --depth 1 origin "$ref"
    git -C "$dest" -c advice.detachedHead=false checkout -q -f FETCH_HEAD
    git -C "$dest" clean -q -fdx -e target -e build-ubuntu-24.04
  else
    git -c advice.detachedHead=false clone -q --depth 1 -b "$ref" "$url" "$dest"
  fi
}

# Debian version from the checkout: v26.04 -> 26.04, v26.04-5-gabc -> 26.04+git5.abc
git_version() { # dir
  local d
  git -C "$1" fetch -q --depth 50 --tags origin 2>/dev/null || true
  d=$(git -C "$1" describe --tags --always)
  d=${d#v}
  if [[ $d =~ ^([0-9][^-]*)-([0-9]+)-g([0-9a-f]+)$ ]]; then
    d="${BASH_REMATCH[1]}+git${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  elif [[ ! $d =~ ^[0-9] ]]; then
    d="0+git.$d"
  fi
  echo "$d"
}

mount_chroot() { # dir
  local c=$1
  mountpoint -q "$c/proc"    || mount -t proc proc "$c/proc"
  mountpoint -q "$c/sys"     || mount -t sysfs sys "$c/sys"
  mountpoint -q "$c/dev"     || mount --bind /dev "$c/dev"
  mountpoint -q "$c/dev/pts" || mount -t devpts devpts "$c/dev/pts"
  mountpoint -q "$c/run"     || mount -t tmpfs tmpfs "$c/run"
}

umount_chroot() { # dir
  local c=$1 m
  for m in run dev/pts dev sys proc; do
    mountpoint -q "$c/$m" 2>/dev/null && umount -l "$c/$m"
  done
  return 0
}

in_chroot() { chroot "$CHROOT" /usr/bin/env -i \
  PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

# Hands files written as root back to the user who started the build.
give_back() { chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$@"; }
