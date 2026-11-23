#!/usr/bin/env bash
# Stage 3: casper tree, GRUB for UEFI (shim + Canonical-signed GRUB, Secure Boot) and BIOS,
# hybrid ISO bootable from optical media and USB sticks.
set -euo pipefail
source /src/scripts/lib.sh

[[ -x "$CHROOT/usr/bin/niri" ]] || die "no rootfs in $CHROOT: run the rootfs stage first"
umount_chroot "$CHROOT"

rm -rf "$ISO_TREE"
mkdir -p "$ISO_TREE"/{casper,.disk,boot/grub,EFI/boot} "$OUT"

log "kernel and initrd"
kernel=$(find "$CHROOT/boot" -maxdepth 1 -name 'vmlinuz-*' | sort -V | tail -n1)
[[ -n "$kernel" ]] || die "no kernel in $CHROOT/boot"
kver=${kernel##*/vmlinuz-}
cp "$kernel" "$ISO_TREE/casper/vmlinuz"
cp "$CHROOT/boot/initrd.img-$kver" "$ISO_TREE/casper/initrd"

log "squashfs"
chroot "$CHROOT" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO_TREE/casper/filesystem.manifest"
du -sx --block-size=1 "$CHROOT" | cut -f1 > "$ISO_TREE/casper/filesystem.size"
# shellcheck disable=SC2086
mksquashfs "$CHROOT" "$ISO_TREE/casper/filesystem.squashfs" -noappend -wildcards \
  -e 'proc/*' -e 'sys/*' -e 'dev/*' -e 'run/*' -e 'tmp/*' $SQUASHFS_COMP

date_tag=$(date -u +%Y%m%d)
echo "$DISTRO_NAME $DISTRO_VERSION LTS \"$date_tag\" - amd64 ($date_tag)" > "$ISO_TREE/.disk/info"
touch "$ISO_TREE/.disk/base_installable"
echo "full_cd/single" > "$ISO_TREE/.disk/cd_type"

log "grub"
cat > "$ISO_TREE/boot/grub/grub.cfg" <<EOF
search --no-floppy --set=root --file /.disk/info
set timeout=10
set default=0

menuentry "Try or install $DISTRO_NAME" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper quiet ---
    initrd /casper/initrd
}
menuentry "Try or install $DISTRO_NAME (safe graphics)" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper nomodeset quiet ---
    initrd /casper/initrd
}
if [ "\$grub_platform" = "efi" ]; then
    menuentry "UEFI firmware settings" {
        fwsetup
    }
fi
EOF

# UEFI: shim and the signed CD GRUB from the image itself. gcdx64 finds the ISO through
# /.disk/info and reads /boot/grub/grub.cfg.
# shimx64.efi.signed is an alternatives link (.latest or .previous), absolute inside the image.
shim="$CHROOT$(chroot "$CHROOT" readlink -f /usr/lib/shim/shimx64.efi.signed)"
[[ -f "$shim" ]] || die "shimx64.efi.signed not found in the image"
log "shim: ${shim#"$CHROOT"}"
gcd="$CHROOT/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed"
[[ -f "$gcd" ]] || die "gcdx64.efi.signed not found in the image"
cp "$shim" "$ISO_TREE/EFI/boot/bootx64.efi"
cp "$CHROOT/usr/lib/shim/mmx64.efi" "$ISO_TREE/EFI/boot/mmx64.efi"
cp "$gcd" "$ISO_TREE/EFI/boot/grubx64.efi"
cp -r "$CHROOT/usr/lib/grub/x86_64-efi" "$ISO_TREE/boot/grub/"

efi_img=/work/efi.img
rm -f "$efi_img"
mkfs.vfat -C -n UEFI "$efi_img" 10240 >/dev/null
mmd -i "$efi_img" ::/EFI ::/EFI/boot
mcopy -i "$efi_img" "$ISO_TREE"/EFI/boot/{bootx64.efi,mmx64.efi,grubx64.efi} ::/EFI/boot/

# BIOS: El Torito core image from the builder's GRUB, with its modules on the ISO.
cp -r /usr/lib/grub/i386-pc "$ISO_TREE/boot/grub/"
grub-mkimage -O i386-pc-eltorito -p /boot/grub -o "$ISO_TREE/boot/grub/i386-pc/eltorito.img" \
  biosdisk iso9660 part_msdos part_gpt fat ext2 normal configfile search search_fs_file \
  search_label linux echo test ls cat chain reboot halt all_video gfxterm font

log "iso"
iso="$OUT/$ISO_BASENAME-$date_tag.iso"
rm -f "$iso" "$iso.sha256"
xorriso -as mkisofs -r -V "$ISO_LABEL" -o "$iso" -J -joliet-long -l -iso-level 3 \
  --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  -partition_offset 16 --mbr-force-bootable \
  -append_partition 2 0xef "$efi_img" -appended_part_as_gpt \
  -c /boot.catalog \
  -b /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
  -eltorito-alt-boot -e '--interval:appended_partition_2:all::' -no-emul-boot \
  "$ISO_TREE"
(cd "$OUT" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256")
cp "$ISO_TREE/casper/filesystem.manifest" "$OUT/$ISO_BASENAME-$date_tag.manifest"
give_back "$OUT"
log "$iso ($(du -h "$iso" | cut -f1))"
