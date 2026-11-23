# Builder image: Ubuntu 24.04 with the tools for the chroot, the ISO and the source packages.
FROM ubuntu:24.04

ARG RUST_TOOLCHAIN=stable
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Image tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg debootstrap squashfs-tools xorriso mtools dosfstools \
      grub-common grub-pc-bin \
      build-essential devscripts equivs dpkg-dev fakeroot file clang pkg-config meson ninja-build hwdata \
 && rm -rf /var/lib/apt/lists/*

# niri and xwayland-satellite
RUN apt-get update && apt-get install -y --no-install-recommends \
      libudev-dev libgbm-dev libxkbcommon-dev libegl-dev libwayland-dev libinput-dev libdbus-1-dev \
      libsystemd-dev libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev \
      libxcb1-dev libxcb-cursor-dev \
 && rm -rf /var/lib/apt/lists/*

# Noctalia (debian/control of the ubuntu-24.04 branch)
RUN apt-get update && apt-get install -y --no-install-recommends \
      debhelper g++-14 libwayland-dev wayland-protocols libegl-dev libgles-dev libepoxy-dev \
      libfreetype-dev libfontconfig-dev libcairo2-dev libpango1.0-dev libharfbuzz-dev libxkbcommon-dev \
      libglib2.0-dev libsecret-1-dev libsodium-dev libsdbus-c++-dev libpipewire-0.3-dev \
      libwireplumber-0.4-dev libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev \
      libcurl4-openssl-dev libwebp-dev libjxl-dev libsndfile1-dev librsvg2-dev libqalculate-dev \
      libxml2-dev libmd4c-dev libtomlplusplus-dev libical-dev nlohmann-json3-dev libstb-dev libjemalloc-dev \
 && rm -rf /var/lib/apt/lists/*

# Noctalia Greeter (private wlroots 0.20 stack)
RUN apt-get update && apt-get install -y --no-install-recommends \
      bison greetd dbus libinput-dev libudev-dev libseat-dev libgbm-dev libegl-dev libgles-dev \
      libliftoff-dev liblcms2-dev libfreetype-dev libfontconfig-dev libcairo2-dev \
      libpango1.0-dev libharfbuzz-dev libglib2.0-dev librsvg2-dev libxml2-dev \
      libtomlplusplus-dev nlohmann-json3-dev libwebp-dev libjxl-dev libffi-dev libexpat1-dev \
 && rm -rf /var/lib/apt/lists/*

# Rust: niri needs rustc >= 1.87, noble ships 1.75
RUN curl -sSf https://sh.rustup.rs | CARGO_HOME=/opt/cargo sh -s -- -y --profile minimal \
      --default-toolchain "$RUST_TOOLCHAIN" --no-modify-path \
 && chmod -R a+rX /opt/cargo /opt/rustup
