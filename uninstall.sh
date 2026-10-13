#!/usr/bin/env bash
# zen-xe uninstall.sh - remove the patched xe DKMS module and go back to the stock driver.
#
#   sudo ./uninstall.sh [--no-initramfs] [--keep-mok-conf]
#
# Removes the DKMS package for every kernel, its sources and cache, the initramfs
# configuration snippet, regenerates the initramfs and runs depmod. The Machine Owner Key
# (and its enrollment) are left alone: other DKMS modules may use them. Reboot afterwards.
set -euo pipefail
ZX_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$ZX_ROOT/lib/common.sh"
DO_INITRAMFS=1 KEEP_CONF=0
while (( $# )); do
	case $1 in
	--no-initramfs) DO_INITRAMFS=0 ;;
	--keep-mok-conf) KEEP_CONF=1 ;;
	-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | cut -c3-; exit 0 ;;
	*) die "unknown option $1" ;;
	esac; shift
done
need_root "$@"
detect_distro

found=0
for v in $(dkms status -m "$ZX_NAME" 2>/dev/null | sed -n "s|^$ZX_NAME/\([^,]*\),.*|\1|p" | sort -u); do
	found=1
	dkms remove -m "$ZX_NAME" -v "$v" --all && ok "removed DKMS $ZX_NAME/$v"
	rm -rf "/usr/src/$ZX_NAME-$v"
done
rm -rf /usr/src/$ZX_NAME-* "$ZX_CACHE"
# leftovers from a hand-installed override of the same driver
for d in /lib/modules/*/updates/xe-vrr; do [[ -d $d ]] && { rm -rf "$d"; found=1; }; done
for k in /lib/modules/*/; do [[ -d $k/kernel ]] && depmod "$(basename "$k")"; done
(( found )) || info "no zen-xe module was installed"
if [[ -f $ZX_STATE/wrote-dkms-conf && $KEEP_CONF == 0 ]]; then rm -f "$ZX_DKMS_CONF"; fi
if (( DO_INITRAMFS )); then
	initramfs_unconfigure
	info "regenerating the initramfs ($(initramfs_tool))..."
	initramfs_regenerate
fi
# dkms_regenerates_initramfs (Fedora) already ran once at "dkms remove", before the snippet was
# gone; the explicit run above makes the images match the configuration again.
rm -rf "$ZX_STATE"
ok "stock xe will be used after the next reboot: $(xe_module_path)"
