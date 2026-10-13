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

* Hardware: ASUS Zenbook Duo UX8407AA (checked; `--any-hardware` for other Panther Lake laptops: the VRR
  fixes are generic, the eDP-2 fix is untested elsewhere and can be turned off with `xe.zenbook_duo_edp2_tcss=0`).
* Kernels: Linux 7.0, 7.1, 7.2 and 7.3 (one patch series per line in `dkms/series/`). Linux 6.x has no
  working Panther Lake display and is refused.
* Distributions: Arch / CachyOS / Manjaro (mkinitcpio), Fedora and openSUSE Tumbleweed (dracut),
  Ubuntu / Debian / Mint / Pop!_OS (initramfs-tools). Anything else: install `dkms`, the kernel headers,
  `git`, `patch` and `pahole`/`dwarves` yourself and the scripts do the rest.
* Secure Boot: supported. DKMS signs the module with a Machine Owner Key; the installer creates one if
  needed and enrolls it with `mokutil` (one-time password, confirmed on the blue MOK screen at the next boot).

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
* `dkms/build.sh` fetches `drivers/gpu/drm/{xe,i915}` of the exact kernel being built for (sparse,
  blob-filtered git clone of the distribution's tree where one exists: `archlinux/linux`,
  `CachyOS/linux`, `zen-kernel`, Fedora `kernel-ark`, Ubuntu's launchpad tree; kernel.org stable
  otherwise), applies `dkms/series/<X.Y>/series`, and builds `xe.ko` out of tree against the installed
  headers. The result lands in `/lib/modules/<kernel>/updates/dkms/`, which depmod prefers over the stock
  module on every mainstream distribution. The initramfs is told to include `xe` by name so early KMS
  uses the patched driver.
* On a kernel update DKMS rebuilds automatically (Arch pacman hooks, Fedora `kernel-install`, Debian
  kernel postinst). If the build fails, the stock xe is used and `./status.sh` says so.
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
  enrolled; `sudo mokutil --import /var/lib/dkms/mok.pub` (or the key `status.sh` shows) and reboot.
* The bottom screen still fails: `journalctl -k -b | grep -E 'PHY B|DDI BUF B'` and open an issue with
  the output and `./status.sh`.
* VRR: it is a separate mode on GNOME/KDE (`…@144+vrr`); when it is on, PSR is off on that panel while
  a fullscreen application presents, which costs a little battery.

## License

GPL-2.0 (the patches are kernel patches; see each file's author and Signed-off-by).
