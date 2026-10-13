#!/usr/bin/env bash
# build.sh KVER KDIR - build a patched xe.ko for kernel release KVER against its build dir KDIR.
#
# Headers packages carry no driver sources, and xe compiles shared display code from
# $(srctree)/drivers/gpu/drm/i915/display, so:
#  1. fetch drivers/gpu/drm/{xe,i915} of the tree the kernel package was built from (sparse,
#     blob-filtered clone; cached under /var/cache/zen-xe/src); the distribution's own tree
#     when it has one with matching tags, kernel.org stable otherwise;
#  2. apply the patch series for this kernel line (series/X.Y/series, with per-patch
#     version constraints);
#  3. build out of tree: a reflink copy of KDIR ("ktree") whose drivers/gpu/drm/{i915,xe}
#     are symlinks into the fetched sources, so xe's Makefile and the trace headers resolve
#     unmodified; then make -C ktree M=src/drivers/gpu/drm/xe modules;
#  4. verify vermagic and that every symbol the module imports is exported by this kernel.
# Environment: ZX_SRC_TREE=<local kernel checkout> skips the network (development).
set -euo pipefail
kver=$1 kdir=$2
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ZX_ROOT=$here
# shellcheck source=lib/common.sh
source "$here/lib/common.sh"
detect_distro
cache=${ZX_CACHE}/src
export GIT_TERMINAL_PROMPT=0
git_net() { timeout "$1" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 "${@:2}"; }
fail() { echo "zen-xe build: $*" >&2; exit 1; }

[[ -f $kdir/.config && -f $kdir/Module.symvers ]] || fail "no kernel build directory at $kdir (headers package missing?)"
[[ ! -f $kdir/include/config/kernel.release ]] || [[ $(<"$kdir/include/config/kernel.release") == "$kver" ]] || fail "$kdir is not the build dir of $kver"

base=$(kernel_base_version "$kver")                  # X.Y.Z of the upstream base
sdir=$(series_dir_for "$base") || true
[[ -n $sdir ]] || fail "no patch series for Linux ${base%.*} (have: $(ls "$here/series" | tr '\n' ' ')); the stock xe stays in use"
echo "zen-xe: kernel $kver (upstream base $base), series $(basename "$sdir")"

# ---- 1. sources ------------------------------------------------------------------------
# candidates "REPO TAG" in order of preference; the first that clones and matches wins.
# Each distribution's own tree is used (Ubuntu's 7.0 carries drm backports from 6.18/7.1, and
# with CONFIG_MODVERSIONS the symbol CRCs must match). kernel.org stable is tried only for a
# kernel whose packaging we do not recognise.
candidates=()
case $kver in
*-arch[0-9]*-*)
	# Arch: 7.2.9-arch1-1 -> github.com/archlinux/linux tag v7.2.9-arch1 (PKGBUILD _srctag)
	[[ $kver =~ -(arch[0-9]+)- ]] && candidates+=("https://github.com/archlinux/linux.git v$base-${BASH_REMATCH[1]}") ;;
*.fc[0-9]*)
	# Fedora: 7.2.9-201.fc44.x86_64 -> kernel-ark tag kernel-7.2.9-1: the fcNN and the
	# per-release hundreds (F43 1xx, F44 2xx, F45 3xx) are added at RPM build time only;
	# rawhide 7.3.0-0.rc7.58.fc45 -> kernel-7.3.0-0.rc7.58 (release kept as is)
	v=${kver%.x86_64}; v=${v%.fc[0-9]*}; rel=${v#*-}; v=${v%%-*}
	[[ $rel =~ ^[0-9]+$ ]] && rel=$(( 10#$rel % 100 ))
	candidates+=("https://gitlab.com/cki-project/kernel-ark.git kernel-$v-$rel") ;;
*-generic|*-lowlatency|*-oem|*-hwe*|*-generic-64k)
	# Ubuntu: the package version holds the upload number uname lacks: 7.0.0-38.38 (GA) or
	# 7.0.0-38.38~24.04.4 (HWE). Tags: Ubuntu-7.0.0-38.38 in the launchpad tree of this release,
	# Ubuntu-hwe-7.0-7.0.0-38.38_24.04.4 in the tree of the release the HWE kernel runs on.
	pv=$(dpkg-query -W -f '${Version}' "linux-modules-$kver" 2>/dev/null || dpkg-query -W -f '${Version}' "linux-image-$kver" 2>/dev/null || true)
	if [[ -z $pv && $kver == "$(uname -r)" && -r /proc/version_signature ]]; then
		pv=$(cut -d' ' -f2 /proc/version_signature); pv=${pv%-*}       # Ubuntu 7.0.0-38.38-generic 7.0.14
	fi
	codename=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}")
	if [[ -n $pv && -n $codename ]]; then
		lp="https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/$codename"
		if [[ $pv == *~* ]]; then
			up=${pv%%-*}; candidates+=("$lp Ubuntu-hwe-${up%.*}-${pv%%~*}_${pv#*~}")
		else
			candidates+=("$lp Ubuntu-$pv")
		fi
	fi ;;
esac
(( ${#candidates[@]} )) || candidates+=("https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git v$base")

fetch_tree() {   # fetch_tree REPO TAG DEST -> 0 if DEST holds drivers/gpu/drm/{xe,i915} of TAG
	local repo=$1 tag=$2 dest=$3 tmp
	tmp=$(mktemp -d "$here/src.XXXXXX")
	# launchpad ignores --filter ("filtering not recognized by server"): there the depth-1 clone is
	# the whole tree (~280 MB), which is why the result is cached. github/gitlab send ~15 MB.
	if git_net 1800 -c advice.detachedHead=false clone -q --depth 1 --filter=blob:none --no-checkout --branch "$tag" "$repo" "$tmp" 2>"$tmp.log" &&
	   git -C "$tmp" sparse-checkout set --no-cone /drivers/gpu/drm/xe/ /drivers/gpu/drm/i915/ /Makefile 2>>"$tmp.log" &&
	   git_net 1800 -C "$tmp" checkout -q 2>>"$tmp.log" && [[ -d $tmp/drivers/gpu/drm/xe ]]; then
		git -C "$tmp" rev-parse HEAD >"$tmp/COMMIT"; echo "$repo $tag" >"$tmp/ORIGIN"
		rm -rf "$tmp/.git" "$tmp.log"; mkdir -p "$(dirname "$dest")"; rm -rf "$dest"; mv "$tmp" "$dest"
		return 0
	fi
	sed 's/^/  git: /' "$tmp.log" 2>/dev/null | head -n3 >&2; rm -rf "$tmp" "$tmp.log"; return 1
}

rm -rf "$here/src"
if [[ -n ${ZX_SRC_TREE:-} ]]; then
	echo "zen-xe: sources from local tree $ZX_SRC_TREE"
	mkdir -p "$here/src/drivers/gpu/drm"
	cp -a --reflink=auto "$ZX_SRC_TREE/drivers/gpu/drm/xe" "$ZX_SRC_TREE/drivers/gpu/drm/i915" "$here/src/drivers/gpu/drm/"
	cp "$ZX_SRC_TREE/Makefile" "$here/src/Makefile"
else
	got=
	for c in "${candidates[@]}"; do
		read -r repo tag <<<"$c"
		key=$(printf '%s' "$repo@$tag" | tr -c 'A-Za-z0-9._-' '_')
		if [[ -d $cache/$key/drivers/gpu/drm/xe ]]; then
			echo "zen-xe: sources from cache: $repo $tag"
		else
			echo "zen-xe: fetching $repo $tag"
			fetch_tree "$repo" "$tag" "$cache/$key" || { echo "zen-xe: not available, trying the next source" >&2; continue; }
		fi
		cp -a --reflink=auto "$cache/$key" "$here/src"; got=1; break
	done
	[[ -n $got ]] || fail "could not fetch the kernel sources for $kver (network? unknown kernel flavour?)"
	ls -1dt "$cache"/*/ 2>/dev/null | tail -n +4 | xargs -r rm -rf     # keep the three newest trees
fi
read -r v p s <<<"$(sed -n -E 's/^(VERSION|PATCHLEVEL|SUBLEVEL) *= *(.*)$/\2/p' "$here/src/Makefile" | tr '\n' ' ')"
[[ "$v.$p.$s" == "$base" ]] || fail "fetched sources are $v.$p.$s, kernel is $base"

# ---- 2. patches ------------------------------------------------------------------------
applied=0
while read -r name constraint _; do
	[[ -n $name && $name != \#* ]] || continue
	if [[ -n $constraint ]]; then
		case $constraint in
		'<'*)  verlt "$base" "${constraint#<}"  || { echo "zen-xe: skip $name ($constraint)"; continue; } ;;
		'>='*) verge "$base" "${constraint#>=}" || { echo "zen-xe: skip $name ($constraint)"; continue; } ;;
		*) fail "bad constraint '$constraint' in $sdir/series" ;;
		esac
	fi
	echo "zen-xe: apply $name"
	patch -d "$here/src" -p1 --forward --no-backup-if-mismatch --quiet <"$sdir/$name" || fail "patch $name does not apply to $kver"
	applied=$((applied + 1))
done <"$sdir/series"
(( applied > 0 )) || fail "no patch applied; nothing to build"

# ---- 3. build --------------------------------------------------------------------------
kt=$here/ktree
rm -rf "$kt"; cp -a --reflink=auto "$kdir/." "$kt"
for d in i915 xe; do rm -rf "$kt/drivers/gpu/drm/$d"; ln -s "$here/src/drivers/gpu/drm/$d" "$kt/drivers/gpu/drm/$d"; done
llvm=(); grep -q '^CONFIG_CC_IS_CLANG=y' "$kdir/.config" && llvm=(LLVM=1)
make -C "$kt" M="$here/src/drivers/gpu/drm/xe" "${llvm[@]}" KCPPFLAGS="-fmacro-prefix-map=$kt/=" -j"$(nproc)" modules 2>&1 | tee "$here/make-xe.log"
[[ ${PIPESTATUS[0]} == 0 ]] || fail "make failed (see make-xe.log)"
rm -rf "$kt"
ko=$here/src/drivers/gpu/drm/xe/xe.ko
[[ -f $ko ]] || fail "xe.ko was not produced"

# ---- 4. verify -------------------------------------------------------------------------
modinfo -F vermagic "$ko" | grep -q "^$kver " || fail "vermagic $(modinfo -F vermagic "$ko") does not match $kver"
grep -qiE 'modpost: .*(undefined|mismatch)' "$here/make-xe.log" && fail "modpost reported undefined symbols or section mismatches"
missing=$(comm -23 <(nm -u "$ko" | awk '{print $2}' | sed 's/^__crc_//' | sort -u) \
                   <(awk '{print $2}' "$kdir/Module.symvers" | sort -u) | grep -vE '^(__fentry__|__stack_chk_fail|__x86_return_thunk|__x86_indirect_thunk_|_printk|__fortify_panic|__ubsan)' || true)
[[ -z $missing ]] || fail "module imports symbols this kernel does not export: $(echo "$missing" | tr '\n' ' ')"
if grep -q '^CONFIG_MODVERSIONS=y' "$kdir/.config"; then
	# Ubuntu: every imported symbol carries a CRC; a mismatch would make the module unloadable
	bad=$(modprobe --dump-modversions "$ko" | awk 'NR==FNR { crc[$2]=$1; next } ($2 in crc) && crc[$2] != $1 { print $2 }' - "$kdir/Module.symvers" || true)
	[[ -z $bad ]] || fail "symbol CRCs differ from this kernel's Module.symvers (wrong source tree?): $(echo "$bad" | head -n5 | tr '\n' ' ')"
fi
modinfo -p "$ko" | grep -q '^zenbook_duo_edp2_tcss:' || echo "zen-xe: note: this series has no eDP-2 TCSS patch" >&2
echo "zen-xe: built $(sha256sum "$ko" | cut -c1-16) for $kver ($applied patches)"
