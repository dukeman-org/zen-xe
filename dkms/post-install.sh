#!/usr/bin/env bash
# DKMS POST_INSTALL hook: post-install.sh KVER. On distributions whose kernel-update
# sequence is known to rebuild the initramfs *after* DKMS (Arch pacman hooks, Fedora
# kernel-install, Debian/Ubuntu kernel postinst), do nothing. Elsewhere regenerate the
# initramfs of that kernel when one already exists, so the patched xe reaches early KMS.
set -u
ZX_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$ZX_ROOT/lib/common.sh"
detect_distro
case $ZX_FAMILY in arch|fedora|debian) exit 0 ;; esac
k=${1:-}
[[ -n $k ]] || exit 0
case $(initramfs_tool) in
dracut)          [[ -f /boot/initramfs-$k.img || -f /boot/initrd-$k ]] && initramfs_regenerate "$k" ;;
initramfs-tools) [[ -f /boot/initrd.img-$k ]] && initramfs_regenerate "$k" ;;
mkinitcpio)      initramfs_regenerate "$k" ;;
esac
exit 0
