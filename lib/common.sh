# shellcheck shell=bash
# zen-xe/lib/common.sh - helpers shared by install.sh, uninstall.sh, status.sh and the DKMS
# Sourced, never run. Expects ZX_ROOT to be the project directory (or the DKMS source directory).

ZX_NAME=zen-xe
ZX_VERSION=$(tr -d '[:space:]' <"$ZX_ROOT/VERSION")
ZX_SRC=/usr/src/$ZX_NAME-$ZX_VERSION
ZX_CACHE=${ZX_CACHE:-/var/cache/zen-xe}
ZX_STATE=/var/lib/zen-xe
ZX_DKMS_CONF=/etc/dkms/framework.conf.d/zen-xe.conf
ZX_DEFAULT_KEY=/var/lib/dkms/mok.key
ZX_DEFAULT_CERT=/var/lib/dkms/mok.pub

if [[ -t 1 ]]; then C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else C_RED= C_GREEN= C_YELLOW= C_BOLD= C_RESET=; fi
info() { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
need_root() { (( EUID == 0 )) || die "run as root: sudo $0 $*"; }

# ---- distribution ----------------------------------------------------------------------
# ZX_FAMILY: arch | debian (Ubuntu) | fedora | unknown (package manager + initramfs conventions)
detect_distro() {
	local id like
	id=$(. /etc/os-release 2>/dev/null; echo "${ID:-}")
	like=$(. /etc/os-release 2>/dev/null; echo "${ID_LIKE:-}")
	ZX_DISTRO=${id:-unknown}
	ZX_DKMS_DISTRO=${like%% *}; ZX_DKMS_DISTRO=${ZX_DKMS_DISTRO:-$id}   # what dkms itself keys on (ID_LIKE[0], else ID)
	case " $id $like " in
	*" arch "*) ZX_FAMILY=arch ;;
	*" debian "*|*ubuntu*|*" pop "*|*linuxmint*|*" mint "*) ZX_FAMILY=debian ;;
	*fedora*|*rhel*|*nobara*|*centos*) ZX_FAMILY=fedora ;;
	*) ZX_FAMILY=unknown ;;
	esac
}

pkg_install() {   # pkg_install PKG... (only the missing ones are installed)
	(( $# )) || return 0
	case $ZX_FAMILY in
	arch)   pacman -S --needed --noconfirm "$@" ;;
	debian) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
	fedora) dnf install -y "$@" ;;
	*) die "install these packages yourself, then re-run: $*" ;;
	esac
}

pkg_installed() {   # pkg_installed PKG
	case $ZX_FAMILY in
	arch)   pacman -Q "$1" >/dev/null 2>&1 ;;
	debian) dpkg-query -W -f '${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
	fedora) rpm -q "$1" >/dev/null 2>&1 ;;
	*) return 1 ;;
	esac
}

# ---- kernels ---------------------------------------------------------------------------
kernel_build_dir() { echo "/lib/modules/$1/build"; }
headers_present() { [[ -f $(kernel_build_dir "$1")/Module.symvers && -f $(kernel_build_dir "$1")/.config ]]; }

# Name of the headers/devel package for kernel release $1 on this distribution.
headers_pkg() {
	local k=$1 pkgbase
	case $ZX_FAMILY in
	arch)   pkgbase=$(cat "/usr/lib/modules/$k/pkgbase" 2>/dev/null || echo linux); echo "$pkgbase-headers" ;;
	debian) echo "linux-headers-$k" ;;
	fedora) echo "kernel-devel-$k" ;;
	*)      echo "" ;;
	esac
}

# Upstream base version X.Y.Z of kernel release $1, from its own build Makefile (Ubuntu's
# "7.0.0-23-generic" is really 7.0.14, which only the headers reveal).
kernel_base_version() {
	local mk; mk=$(kernel_build_dir "$1")/Makefile
	[[ -f $mk ]] || { echo "${1%%-*}"; return; }
	local v p s
	v=$(sed -n 's/^VERSION *= *//p' "$mk"); p=$(sed -n 's/^PATCHLEVEL *= *//p' "$mk"); s=$(sed -n 's/^SUBLEVEL *= *//p' "$mk")
	echo "$v.$p.${s:-0}"
}

# version comparison: verlt 7.2.9 7.2.10 -> true
verlt() { [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1) == "$1" ]]; }
verge() { ! verlt "$1" "$2"; }

# Patch series directory for kernel base version $1 (X.Y.Z -> series/X.Y), or "" if none.
series_dir_for() {   # works from the project dir (dkms/series) and from the DKMS source dir (series)
	local xy=${1%.*} d
	for d in "$ZX_ROOT/dkms/series/$xy" "$ZX_ROOT/series/$xy"; do
		[[ -f $d/series ]] && { echo "$d"; return 0; }
	done
	return 1
}

# ---- initramfs -------------------------------------------------------------------------
initramfs_tool() {
	# Ubuntu 26.04 installs dracut by default (and a compat update-initramfs wrapper); systems
	# upgraded from 24.04 keep initramfs-tools. Ask dpkg which one is the real generator.
	if have mkinitcpio && [[ -f /etc/mkinitcpio.conf ]]; then echo mkinitcpio
	elif [[ $ZX_FAMILY == debian ]] && pkg_installed initramfs-tools && ! pkg_installed dracut; then echo initramfs-tools
	elif have dracut; then echo dracut
	elif have update-initramfs && [[ -d /etc/initramfs-tools ]]; then echo initramfs-tools
	else echo none; fi
}

# Fedora's dkms package sets post_transaction="dracut --regenerate-all --force", so every
# dkms install/remove already rebuilds all initramfs images.
dkms_regenerates_initramfs() {
	grep -hs '^[[:space:]]*post_transaction[[:space:]]*=' /etc/dkms/framework.conf /etc/dkms/framework.conf.d/*.conf 2>/dev/null | grep -q dracut
}

# Make sure "xe" is included by name, so the override under updates/ is what early KMS gets.
initramfs_configure() {
	case $(initramfs_tool) in
	mkinitcpio)
		install -d /etc/mkinitcpio.conf.d
		cat >/etc/mkinitcpio.conf.d/zen-xe.conf <<'CONF'
# zen-xe: the kms hook only picks GPU drivers from kernel/drivers/gpu/drm/; name xe
# explicitly so the patched module in updates/dkms/ goes into the initramfs.
MODULES+=(xe)
CONF
		;;
	dracut)
		install -d /etc/dracut.conf.d
		printf '# zen-xe: include the patched xe (updates/dkms) for early KMS\nadd_drivers+=" xe "\n' >/etc/dracut.conf.d/zen-xe.conf
		;;
	initramfs-tools)
		grep -qx 'xe' /etc/initramfs-tools/modules 2>/dev/null || printf '# zen-xe: patched xe for early KMS\nxe\n' >>/etc/initramfs-tools/modules
		;;
	none) warn "no initramfs generator found; make sure your boot image contains the patched xe" ;;
	esac
}

initramfs_unconfigure() {
	rm -f /etc/mkinitcpio.conf.d/zen-xe.conf /etc/dracut.conf.d/zen-xe.conf
	[[ -f /etc/initramfs-tools/modules ]] && sed -i '/^# zen-xe: patched xe for early KMS$/d; /^xe$/d' /etc/initramfs-tools/modules
	return 0
}

# initramfs_regenerate [KVER]   (no argument: every installed kernel)
initramfs_regenerate() {
	local k=${1:-}
	case $(initramfs_tool) in
	mkinitcpio)
		if [[ -n $k && -f /usr/lib/modules/$k/pkgbase ]]; then mkinitcpio -p "$(cat "/usr/lib/modules/$k/pkgbase")"
		else mkinitcpio -P; fi ;;
	dracut)
		if [[ -n $k ]]; then dracut -f --kver "$k"; else dracut -f --regenerate-all; fi ;;
	initramfs-tools)
		update-initramfs -u -k "${k:-all}" ;;
	none) warn "initramfs not regenerated (no generator found)" ;;
	esac
}

# ---- Secure Boot / module signing ------------------------------------------------------
sb_enabled() {
	if have mokutil; then mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; return; fi
	local f; for f in /sys/firmware/efi/efivars/SecureBoot-*; do
		[[ -r $f ]] && [[ $(od -An -tu1 -j4 -N1 "$f" | tr -d ' ') == 1 ]] && return 0
	done
	return 1
}

# Key and certificate DKMS will sign with: "KEY CERT". Order: an explicit DKMS framework
# setting; on Ubuntu (dkms distro "ubuntu*") the shim-signed MOK that dkms creates through
# update-secureboot-policy; otherwise DKMS's own default (generated on first build).
dkms_signing_files() {
	local key= cert= f
	for f in /etc/dkms/framework.conf /etc/dkms/framework.conf.d/*.conf; do
		[[ -f $f ]] || continue
		local k c
		k=$(sed -n 's/^[[:space:]]*mok_signing_key[[:space:]]*=[[:space:]]*//p' "$f" | tail -n1 | tr -d '"'"'")
		c=$(sed -n 's/^[[:space:]]*mok_certificate[[:space:]]*=[[:space:]]*//p' "$f" | tail -n1 | tr -d '"'"'")
		[[ -n $k ]] && key=$k; [[ -n $c ]] && cert=$c
	done
	if [[ -z $key && ( $ZX_DKMS_DISTRO == ubuntu* || -f /var/lib/shim-signed/mok/MOK.priv ) ]]; then
		key=/var/lib/shim-signed/mok/MOK.priv cert=${cert:-/var/lib/shim-signed/mok/MOK.der}
	fi
	echo "${key:-$ZX_DEFAULT_KEY} ${cert:-$ZX_DEFAULT_CERT}"
}

# cert_der CERT -> path of a DER copy (the file itself if already DER)
cert_der() {
	if openssl x509 -inform DER -in "$1" -noout 2>/dev/null; then echo "$1"; return; fi
	local t; t=$(mktemp); openssl x509 -inform PEM -in "$1" -outform DER -out "$t" 2>/dev/null && echo "$t"
}

mok_enrolled() { mokutil --test-key "$1" 2>&1 | grep -q 'already enrolled'; }   # mokutil answers on stderr, exit 1

# ---- the running override -------------------------------------------------------------
xe_module_path() { modinfo -n -k "${1:-$(uname -r)}" xe 2>/dev/null; }
# dkms installs under updates/dkms (Ubuntu, Arch) or extra/ (Fedora) and archives the stock
# module in /var/lib/dkms/<name>/original_module/, so either path means ours is selected.
xe_is_override() { local p; p=$(xe_module_path "${1:-}"); [[ $p == */updates/* || $p == */extra/* ]]; }
