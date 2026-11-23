#!/usr/bin/env bash
# Stage 1: builds niri, xwayland-satellite, Noctalia and Noctalia Greeter as .deb for noble.
# A package is rebuilt only when the source commit changes ($DEBS/<name>.commit).
set -euo pipefail
source /src/scripts/lib.sh

mkdir -p "$SRC_DIR" "$DEBS" "$CARGO_HOME"

up_to_date() { # name dir
  local commit
  commit=$(git -C "$2" rev-parse HEAD)
  [[ -f "$DEBS/$1.commit" && "$(cat "$DEBS/$1.commit")" == "$commit" ]] \
    && compgen -G "$DEBS/$1_*.deb" >/dev/null
}

mark_built() { # name dir
  git -C "$2" rev-parse HEAD > "$DEBS/$1.commit"
}

# Binary package from a staged tree; Depends computed by dpkg-shlibdeps.
make_deb() { # name version stagedir extra-depends recommends description
  local name=$1 version=$2 root=$3 extra=$4 recommends=$5 description=$6
  local tmp shlibs bins
  tmp=$(mktemp -d)
  mkdir -p "$tmp/debian"
  printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$name" "$name" > "$tmp/debian/control"
  mapfile -t bins < <(find "$root" -type f -exec sh -c 'file -b "$1" | grep -q ELF' _ {} \; -print)
  shlibs=$(cd "$tmp" && dpkg-shlibdeps -O "${bins[@]}" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
  rm -rf "$tmp"

  mkdir -p "$root/DEBIAN"
  {
    echo "Package: $name"
    echo "Version: $version"
    echo "Architecture: amd64"
    echo "Maintainer: Nirintu builder <root@localhost>"
    echo "Installed-Size: $(du -sk --exclude=DEBIAN "$root" | cut -f1)"
    echo "Depends: ${shlibs}${extra:+, $extra}"
    [[ -n "$recommends" ]] && echo "Recommends: $recommends"
    echo "Section: x11"
    echo "Priority: optional"
    echo "Description: $description"
  } > "$root/DEBIAN/control"
  rm -f "$DEBS/${name}"_*.deb
  dpkg-deb --root-owner-group -Zxz --build "$root" "$DEBS/${name}_${version}_amd64.deb" >/dev/null
  log "built $(basename "$DEBS/${name}_${version}_amd64.deb")"
}

build_niri() {
  local dir="$SRC_DIR/niri" version stage
  checkout "$NIRI_REPO" "$NIRI_REF" "$dir"
  if up_to_date niri "$dir"; then log "niri up to date"; return; fi
  log "niri $NIRI_REF"
  version="$(git_version "$dir")-1~noble"
  (cd "$dir" && cargo build --release --locked)
  stage=$(mktemp -d)
  install -Dm755 "$dir/target/release/niri"            "$stage/usr/bin/niri"
  install -Dm755 "$dir/resources/niri-session"         "$stage/usr/bin/niri-session"
  install -Dm644 "$dir/resources/niri.desktop"         "$stage/usr/share/wayland-sessions/niri.desktop"
  install -Dm644 "$dir/resources/niri-portals.conf"    "$stage/usr/share/xdg-desktop-portal/niri-portals.conf"
  install -Dm644 "$dir/resources/niri.service"         "$stage/usr/lib/systemd/user/niri.service"
  install -Dm644 "$dir/resources/niri-shutdown.target" "$stage/usr/lib/systemd/user/niri-shutdown.target"
  install -Dm644 "$dir/resources/default-config.kdl"   "$stage/usr/share/niri/default-config.kdl"
  install -Dm644 "$dir/LICENSE"                        "$stage/usr/share/doc/niri/copyright"
  make_deb niri "$version" "$stage" "" \
    "xwayland-satellite, xdg-desktop-portal-gnome, xdg-desktop-portal-gtk, gnome-keyring" \
    "Scrollable-tiling Wayland compositor"
  rm -rf "$stage"
  mark_built niri "$dir"
}

build_xwayland_satellite() {
  local dir="$SRC_DIR/xwayland-satellite" version stage
  checkout "$XWS_REPO" "$XWS_REF" "$dir"
  if up_to_date xwayland-satellite "$dir"; then log "xwayland-satellite up to date"; return; fi
  log "xwayland-satellite $XWS_REF"
  version="$(git_version "$dir")-1~noble"
  (cd "$dir" && cargo build --release --locked)
  stage=$(mktemp -d)
  install -Dm755 "$dir/target/release/xwayland-satellite" "$stage/usr/bin/xwayland-satellite"
  install -Dm644 "$dir/LICENSE"                           "$stage/usr/share/doc/xwayland-satellite/copyright"
  make_deb xwayland-satellite "$version" "$stage" "xwayland" "" \
    "Xwayland outside your Wayland compositor"
  rm -rf "$stage"
  mark_built xwayland-satellite "$dir"
}

build_noctalia() {
  local dir="$SRC_DIR/noctalia"
  checkout "$NOCTALIA_REPO" "$NOCTALIA_REF" "$dir"
  if up_to_date noctalia "$dir"; then log "noctalia up to date"; return; fi
  log "noctalia $NOCTALIA_REF"
  rm -f "$SRC_DIR"/noctalia_*.deb "$SRC_DIR"/noctalia-dbgsym_* "$SRC_DIR"/noctalia_*.{buildinfo,changes}
  (cd "$dir" && dpkg-buildpackage -b -us -uc --no-sign)
  rm -f "$DEBS"/noctalia_*.deb
  mv "$SRC_DIR"/noctalia_*.deb "$DEBS/"
  log "built $(basename "$DEBS"/noctalia_*.deb)"
  mark_built noctalia "$dir"
}

build_greeter() {
  local dir="$SRC_DIR/noctalia-greeter"
  checkout "$GREETER_REPO" "$GREETER_REF" "$dir"
  if up_to_date noctalia-greeter "$dir"; then log "noctalia-greeter up to date"; return; fi
  log "noctalia-greeter $GREETER_REF"
  rm -f "$dir"/build-ubuntu-24.04/noctalia-greeter_*.deb
  (cd "$dir" && packaging/ubuntu-24.04/build.sh && packaging/ubuntu-24.04/make-deb.sh)
  rm -f "$DEBS"/noctalia-greeter_*.deb
  mv "$dir"/build-ubuntu-24.04/noctalia-greeter_*.deb "$DEBS/"
  log "built $(basename "$DEBS"/noctalia-greeter_*.deb)"
  mark_built noctalia-greeter "$dir"
}

build_niri
build_xwayland_satellite
build_noctalia
build_greeter

{
  for n in niri xwayland-satellite noctalia noctalia-greeter; do
    printf '%-20s %s\n' "$n" "$(cat "$DEBS/$n.commit")"
  done
} > "$DEBS/SOURCES"
give_back "$DEBS"
log "packages in $DEBS"
