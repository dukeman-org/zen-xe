#!/usr/bin/env bash
# zen-xe status.sh - which xe is running, its parameters, DKMS state, kernel errors. No root.
set -u
ZX_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$ZX_ROOT/lib/common.sh"
detect_distro
k=$(uname -r)
pat='PHY B|DDI BUF B|TCSS|flip_done timed out|vblank wait timed out|link training failed|DSB .* poll error|timed out waiting for idle'
echo "kernel         : $k (upstream $(kernel_base_version "$k"))   $ZX_DISTRO / $(initramfs_tool)"
echo "xe module      : $(xe_module_path "$k")"
if xe_is_override "$k"; then ok "patched xe is the module depmod selects"; else warn "stock xe selected (not installed, build failed, or kernel updated without a rebuild)"; fi
signer=$(modinfo -F signer -k "$k" xe 2>/dev/null); echo "signer         : ${signer:-unsigned}"
d=$(dkms status -m zen-xe 2>/dev/null | tr '\n' ';'); echo "dkms           : ${d:-not installed}"
for p in zenbook_duo_edp2_tcss enable_dc_balance enable_psr enable_panel_replay; do
	f=/sys/module/xe/parameters/$p
	if [[ ! -e $f ]]; then v="(not in the loaded module)"
	elif [[ -r $f ]]; then v=$(<"$f")
	else v="(root-only; cmdline: $(grep -o "xe\.$p=[0-9]" /proc/cmdline || echo default))"; fi
	printf 'xe.%-22s %s\n' "$p" "$v"
done
[[ -e /sys/module/xe/parameters/zenbook_duo_edp2_tcss ]] && ok "running xe has the eDP-2 TCSS fix" || warn "running xe is NOT the patched one (reboot pending? see above)"
sb_enabled && echo "secure boot    : on" || echo "secure boot    : off"
for c in /sys/class/drm/card*-eDP-*; do [[ -e $c ]] && echo "$(basename "$c")    : $(cat "$c/status") / $(cat "$c/enabled")"; done
n=$(journalctl -k -b --no-pager -q 2>/dev/null | grep -cE "$pat")
echo "display errors : $n this boot (PHY B / DDI B / flip_done / DSB)"
(( n )) && journalctl -k -b --no-pager -q | grep -E "$pat" | tail -n 5
exit 0
