# zen-xe

Patched Intel **xe** display driver for the 2026 ASUS Zenbook Duo (UX8407AA, Intel Panther Lake) as a
DKMS module: install once, it is rebuilt for every kernel update, and one command removes it.

## What it fixes

| | stock kernel 7.0 – 7.2 | with zen-xe |
|---|---|---|
| **Bottom screen after powering on with the keyboard on it** | eDP-2 fails to light (`PHY B failed to request refclk`), pipe B times out, the laptop can freeze | works ([drm/xe #9196](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196); fix proposed upstream, not merged yet) |
| **Variable refresh rate (VRR)** on the OLED panels | panel stuck at minimum refresh, `DSB 0 poll error` floods, `flip_done timed out`; silently never engages with PSR | works (four fixes from Linux 7.3) |
| Connector detection after resume, shrinker accounting, DC-state writes | minor bugs | three small fixes from 7.3 |

The 7.3 series needs only the bottom-screen fix; everything else is upstream there.

## Supported

* **Distributions:** Ubuntu 26.04 (kernel 7.0, also the 24.04 HWE kernel), Arch Linux (7.2) and
  Fedora 44 (7.2). That is what the scripts know: apt / pacman / dnf, dracut or initramfs-tools /
  mkinitcpio / dracut, and each distribution's own kernel source tree. Derivatives with the same
  package manager and kernel packages usually work unchanged. Only the Arch path has been run on real
  hardware so far; the Ubuntu and Fedora paths follow each distribution's dkms and kernel packaging
  conventions, and the patch series were verified to apply to Ubuntu's `7.0.0-38.38` and Fedora's
  `kernel-7.2.9-1` trees.
* **Kernels:** Linux 7.0, 7.1, 7.2 and 7.3 (one patch series per line in `dkms/series/`, each
  compile-tested; `NOTES.md` there records every backport decision). Linux 6.x has no working Panther
  Lake display and is refused (that includes Arch `linux-lts`).
* **Hardware:** ASUS Zenbook Duo UX8407AA (checked). `--any-hardware` allows other Panther Lake laptops:
  the VRR fixes are generic, the eDP-2 fix is untested elsewhere and can be turned off with
  `xe.zenbook_duo_edp2_tcss=0`.
* **Secure Boot:** supported. DKMS signs the module with a Machine Owner Key; the installer creates one
  if needed and enrolls it with `mokutil` (one-time password, confirmed on the blue MOK screen at the
  next boot). On Ubuntu that is the shim-signed MOK (`/var/lib/shim-signed/mok/`, made and enrolled by
  `update-secureboot-policy`); on Fedora and Arch it is dkms's own `/var/lib/dkms/mok.key` unless
  `/etc/dkms/framework.conf` names another.

## Install

```sh
git clone https://github.com/dukeman-org/zen-xe.git && cd zen-xe
sudo ./install.sh
sudo reboot
./status.sh
```

`status.sh` should say the patched xe is the selected module, that the running driver has the eDP-2 fix, and
report zero display errors.

## Uninstall

```sh
sudo ./uninstall.sh
sudo reboot
```

Removes the DKMS package, sources, cache and initramfs snippet, and regenerates the initramfs. The Machine
Owner Key stays (other DKMS modules may use it).

## How it works

* `install.sh` registers `dkms/` as the DKMS package **zen-xe** and builds it for the running kernel.
* `dkms/build.sh` fetches `drivers/gpu/drm/{xe,i915}` of the exact kernel being built for (sparse git
  clone of the distribution's own tree, cached in `/var/cache/zen-xe`):
  * Arch `7.2.9-arch1-1`: `github.com/archlinux/linux` tag `v7.2.9-arch1` (about 15 MB);
  * Fedora `7.2.9-201.fc44`: `gitlab.com/cki-project/kernel-ark` tag `kernel-7.2.9-1` (the `.fc44` and
    the per-release hundreds are added at RPM build time; about 15 MB);
  * Ubuntu `7.0.0-38-generic`: the launchpad tree of the release, tag `Ubuntu-7.0.0-38.38` (HWE kernels:
    `Ubuntu-hwe-7.0-7.0.0-38.38_24.04.4` in the running release's tree). Launchpad does not support
    partial clones, so this one downloads about 280 MB once per kernel. Ubuntu's 7.0 carries drm
    backports and builds with `CONFIG_MODVERSIONS`, so kernel.org sources would not do; the build also
    checks every imported symbol's CRC against `Module.symvers`;
  * kernel.org stable `vX.Y.Z` only for a kernel whose packaging is not recognised.

  It then applies `dkms/series/<X.Y>/series` and builds `xe.ko` out of tree against the installed headers.
  dkms installs the result under `/lib/modules/<kernel>/updates/dkms/` (Ubuntu, Arch) or `extra/`
  (Fedora) and moves the stock `xe.ko` to `/var/lib/dkms/zen-xe/original_module/` (restored on removal),
  so the patched module is the one depmod finds. The initramfs is told to include `xe` by name so early
  KMS uses the patched driver.
* On a kernel update DKMS rebuilds automatically before the initramfs is regenerated (Arch pacman
  hooks `70-dkms-install` then `90-mkinitcpio-install`, Fedora `kernel-install` plugins `40-dkms` then
  `50-dracut`, Ubuntu `/etc/kernel/postinst.d/dkms` then `dracut` / `initramfs-tools`). If the build
  fails (no network, unknown kernel), the stock xe is used and `./status.sh` says so.
* The module parameter `xe.zenbook_duo_edp2_tcss=0` turns the eDP-2 fix off for one boot;
  `xe.enable_dc_balance=1` restores the VRR DC-balance behaviour.

## Patches

`dkms/series/7.2/` (kernel 7.2.y), in order:

1. `drm/i915/dsb: shift delayed-vblank DSL wait start by one scanline` (7.3)
2. `drm/i915/dsb: Use safe window path when VRR TG is used` (7.3)
3. `drm/i915/display: Ensure a non-zero safe window from PTL onwards` (7.3)
4. `drm/i915/vrr: Disable DC balance by default` (7.3, in stable from 7.2.10; applied only below 7.2.10)
5. `drm/i915/cx0: request TCSS power for the non-TC C20 PHY on PTL port B` (RFC on intel-xe, 2026-10-06,
   by the author of [zenbook-duo-2026-linux](https://github.com/burakgon/zenbook-duo-2026-linux))
6. module parameter `zenbook_duo_edp2_tcss` (off switch / marker)
7. `drm/i915/xe: Enable HPD polling later during system resume` (7.3)
8. `drm/xe: Fix shrinker accounting double-subtraction on nested external pins` (7.3)
9. `drm/i915/display: Mask RO bits in gen9_write_dc_state()` (7.3)

Other series directories hold the same fixes rebased on that kernel line, minus what is already upstream
there (see each `NOTES.md`).

## Troubleshooting

* `./status.sh` says the stock xe is selected: `dkms status zen-xe`, then
  `cat /var/lib/dkms/zen-xe/*/build/make.log`. A failed source fetch (no network at kernel-update time)
  is fixed by `sudo dkms install zen-xe/<version>` later.
* Secure Boot on and the module does not load (`modprobe: Key was rejected by service`): the MOK is not
  enrolled; `sudo mokutil --import /var/lib/dkms/mok.pub` (Ubuntu: `sudo update-secureboot-policy
  --enroll-key`) and reboot. `modinfo xe | grep signer` shows which certificate signed the module.
* The bottom screen still fails: `journalctl -k -b | grep -E 'PHY B|DDI BUF B'` and open an issue with
  the output and `./status.sh`.
* VRR: it is a separate mode on GNOME/KDE (`…@144+vrr`); when it is on, PSR is off on that panel while
  a fullscreen application presents, which costs a little battery.

## License

GPL-2.0 (the patches are kernel patches; see each file's author and Signed-off-by).
