#!/usr/bin/env bash
# zen-xe install.sh - install the patched Intel xe display driver as a DKMS module.
#
#   sudo ./install.sh [options]
#
#   --kernel KVER     build for this kernel release instead of the running one
#   --no-initramfs    do not touch initramfs configuration / images
#   --any-hardware    skip the laptop model check (any Panther Lake Intel GPU)
#   --keep-cache      keep /var/cache/zen-xe from a previous install
#   -h, --help
#
# What it does: checks the machine, installs dkms + kernel headers + build tools, makes
# sure a Machine Owner Key exists and is enrolled when Secure Boot is on (DKMS signs the
# module with it), registers the DKMS package, builds and installs xe.ko into
# /lib/modules/<kernel>/updates/dkms/ (extra/ on Fedora), lists xe in the initramfs configuration and
# regenerates the initramfs. A reboot activates it (xe cannot be swapped while running).
# Everything is undone by uninstall.sh.
set -euo pipefail
ZX_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$ZX_ROOT/lib/common.sh"

KVER=$(uname -r) DO_INITRAMFS=1 ANY_HW=0 KEEP_CACHE=0
while (( $# )); do
	case $1 in
	--kernel) KVER=$2; shift ;;
	--no-initramfs) DO_INITRAMFS=0 ;;
	--any-hardware) ANY_HW=1 ;;
	--keep-cache) KEEP_CACHE=1 ;;
	-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | cut -c3-; exit 0 ;;
	*) die "unknown option $1 (see --help)" ;;
	esac; shift
done
need_root "$@"
detect_distro
info "${C_BOLD}zen-xe $ZX_VERSION${C_RESET}: patched Intel xe for the Zenbook Duo UX8407AA  (distribution: $ZX_DISTRO, family: $ZX_FAMILY)"
[[ $ZX_FAMILY != unknown ]] || warn "not Ubuntu, Arch or Fedora: packages must already be installed (dkms, kernel headers, git, patch, pahole/dwarves)"

# ---- 1. machine ------------------------------------------------------------------------
gpu=$(lspci -n -d 8086: 2>/dev/null | awk '$2 ~ /^03/ {print $3}' | head -n1)
[[ ${gpu:-} == 8086:b0* ]] || { (( ANY_HW )) && warn "no Panther Lake display found (PCI ${gpu:-none}); continuing because of --any-hardware"; } || die "no Intel Panther Lake GPU found (PCI id ${gpu:-none}); these patches are for display version 30 (use --any-hardware to override)"
model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "?")
if [[ $model != *UX8407AA* ]]; then
	(( ANY_HW )) || die "this is a '$model', not an ASUS Zenbook Duo UX8407AA; the eDP-2 power fix is untested elsewhere (use --any-hardware to continue)"
	warn "model '$model': the VRR fixes are generic Panther Lake fixes; the eDP-2 TCSS patch is untested here (xe.zenbook_duo_edp2_tcss=0 turns it off)"
fi
base=$(kernel_base_version "$KVER")
verge "$base" 7.0.0 || die "kernel $KVER is too old (Panther Lake display needs Linux 7.0 or newer)"
sdir=$(series_dir_for "$base") || true
[[ -n $sdir ]] || die "no patch series for Linux ${base%.*} yet (available: $(ls "$ZX_ROOT/dkms/series" | tr '\n' ' '))"
ok "kernel $KVER (upstream $base), patch series ${sdir##*/}"

# ---- 2. conflicts ----------------------------------------------------------------------
if dkms status 2>/dev/null | grep -q '^zenbook-duo-xe/'; then
	die "burakgon's zenbook-duo-2026-linux 'display-edp2-tcss' module is installed (DKMS zenbook-duo-xe); it ships the same xe override. Revert it first: sudo ./duo revert display-edp2-tcss"
fi
for d in /lib/modules/*/updates/xe-vrr; do
	[[ -d $d ]] || continue
	warn "removing the hand-installed override $d (replaced by DKMS)"
	rm -rf "$d"; depmod "$(basename "$(dirname "$(dirname "$d")")")"
done

# ---- 3. packages -----------------------------------------------------------------------
# pahole/dwarves: only Arch headers ship vmlinux, so only there kbuild generates module BTF;
# harmless elsewhere. Module compression: zstd on Ubuntu and Arch, xz on Fedora.
pk=(dkms git patch)
case $ZX_FAMILY in
arch)   pk+=(pahole zstd) ;;
debian) pk+=(dwarves build-essential zstd) ;;
fedora) pk+=(dwarves gcc make elfutils-libelf-devel xz) ;;
esac
if sb_enabled; then
	pk+=(mokutil openssl)
	[[ $ZX_DKMS_DISTRO == ubuntu* ]] && pk+=(shim-signed)   # update-secureboot-policy
fi
hp=$(headers_pkg "$KVER")
if ! headers_present "$KVER" && [[ -n $hp ]]; then pk+=("$hp"); fi
missing=(); for p in "${pk[@]}"; do pkg_installed "$p" || missing+=("$p"); done
if (( ${#missing[@]} )); then
	info "installing: ${missing[*]}"
	pkg_install "${missing[@]}"
fi
headers_present "$KVER" || die "kernel headers for $KVER not found at $(kernel_build_dir "$KVER") (package ${hp:-?})"
grep -q '^CONFIG_CC_IS_CLANG=y' "$(kernel_build_dir "$KVER")/.config" && ! have clang && pkg_install clang llvm lld
ok "build tools present"

# ---- 4. Secure Boot --------------------------------------------------------------------
install -d "$ZX_STATE"
if sb_enabled; then
	read -r key cert <<<"$(dkms_signing_files)"
	if [[ ! -f $key || ! -f $cert ]]; then
		if [[ $key == /var/lib/shim-signed/* ]] && have update-secureboot-policy; then
			info "creating the Machine Owner Key with update-secureboot-policy: $key"
			SHIM_NOTRIGGER=y update-secureboot-policy --new-key
		elif [[ $key == "$ZX_DEFAULT_KEY" ]]; then
			info "creating a Machine Owner Key for DKMS modules: $key"
			install -d -m 700 "$(dirname "$key")"
			openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 -subj "/CN=DKMS module signing key/" \
				-keyout "$key" -outform DER -out "$cert" 2>/dev/null
			chmod 600 "$key"
		else
			die "DKMS is configured to sign with $key, which does not exist"
		fi
		[[ -f $key && -f $cert ]] || die "signing key $key / certificate $cert still missing"
	fi
	# make DKMS's choice explicit when nothing configures it (Ubuntu's shim-signed MOK, or the default)
	if ! grep -qs '^[[:space:]]*mok_signing_key' /etc/dkms/framework.conf /etc/dkms/framework.conf.d/*.conf 2>/dev/null; then
		install -d /etc/dkms/framework.conf.d
		printf '# zen-xe: sign DKMS modules with this Machine Owner Key (Secure Boot)\nmok_signing_key=%s\nmok_certificate=%s\n' "$key" "$cert" >"$ZX_DKMS_CONF"
		touch "$ZX_STATE/wrote-dkms-conf"
	fi
	der=$(cert_der "$cert") || die "cannot read certificate $cert"
	if mok_enrolled "$der"; then
		ok "Secure Boot on; signing key $cert is enrolled"
	else
		info "${C_BOLD}Secure Boot is on and the signing key is not enrolled yet.${C_RESET}"
		info "mokutil will ask you to choose a one-time password. On the next boot a blue 'MOK management'"
		info "screen appears: choose Enroll MOK -> Continue -> Yes, type that password, reboot."
		if have update-secureboot-policy && [[ $key == /var/lib/shim-signed/* ]]; then
			update-secureboot-policy --enroll-key || die "key enrollment failed"
		else
			mokutil --import "$der" || die "mokutil --import failed"
		fi
		touch "$ZX_STATE/mok-enroll-pending"
		warn "without the enrollment the signed module will not load and the stock xe is used"
	fi
else
	ok "Secure Boot off (modules need no signature)"
fi

# ---- 5. DKMS ---------------------------------------------------------------------------
# the initramfs snippet first: Fedora's dkms regenerates every initramfs right after the install
(( DO_INITRAMFS )) && initramfs_configure
for old in $(dkms status -m "$ZX_NAME" 2>/dev/null | sed -n "s|^$ZX_NAME/\([^,]*\),.*|\1|p" | sort -u); do
	dkms remove -m "$ZX_NAME" -v "$old" --all >/dev/null 2>&1 || true
	rm -rf "/usr/src/$ZX_NAME-$old"
done
(( KEEP_CACHE )) || rm -rf "$ZX_CACHE"
rm -rf "$ZX_SRC"; install -d "$ZX_SRC"
cp -a "$ZX_ROOT/dkms/." "$ZX_ROOT/lib" "$ZX_ROOT/VERSION" "$ZX_SRC/"
sed -i "s/@VERSION@/$ZX_VERSION/" "$ZX_SRC/dkms.conf"
dkms add -m "$ZX_NAME" -v "$ZX_VERSION" >/dev/null
info "building xe for $KVER (fetches a few MB of kernel sources; about a minute)..."
if ! dkms install -m "$ZX_NAME" -v "$ZX_VERSION" -k "$KVER"; then
	log=/var/lib/dkms/$ZX_NAME/$ZX_VERSION/build/make.log
	[[ -f $log ]] && { echo; echo "--- last lines of $log:"; tail -n 25 "$log"; }
	die "DKMS build failed; the stock xe stays in use. Nothing else was changed."
fi
path=$(xe_module_path "$KVER")
[[ $path == */updates/dkms/* || $path == */extra/* ]] || die "depmod does not select the new module ($path); check /etc/depmod.d"
signer=$(modinfo -F signer -k "$KVER" xe 2>/dev/null || true)
ok "installed $path${signer:+ (signed by: $signer)}"
modinfo -p -k "$KVER" xe | grep -q '^zenbook_duo_edp2_tcss:' && ok "eDP-2 TCSS power fix present" || warn "this series has no eDP-2 TCSS patch"

# ---- 6. initramfs ----------------------------------------------------------------------
if (( DO_INITRAMFS )); then
	if dkms_regenerates_initramfs; then
		ok "initramfs regenerated by DKMS's post-transaction hook"
	else
		info "regenerating the initramfs ($(initramfs_tool))..."
		initramfs_regenerate "$KVER"
		ok "initramfs updated"
	fi
fi
printf 'version=%s\nkernel=%s\ndate=%s\n' "$ZX_VERSION" "$KVER" "$(date -Is)" >"$ZX_STATE/installed"
echo
ok "${C_BOLD}done. Reboot to start using the patched xe.${C_RESET}"
info "   afterwards:  ./status.sh      (module in use, parameters, kernel errors)"
info "   undo:        sudo ./uninstall.sh"
[[ -f $ZX_STATE/mok-enroll-pending ]] && warn "remember the MOK enrollment screen on the next boot"
exit 0
