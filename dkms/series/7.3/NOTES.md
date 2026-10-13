# 7.3 series (base v7.3-rc7)

Base: v7.3-rc7 (24a19b953e2a, mainline). Worktree: series-work/7.3.

Dropped because already in mainline at v7.3-rc7 (verified by subject with
`git log --oneline v7.3-rc7 -- <file> | grep`):

| commit | subject | in v7.3-rc7 as |
|--------|---------|----------------|
| A | drm/i915/dsb: shift delayed-vblank DSL wait start by one scanline | f7140c7cef30 |
| B | drm/i915/dsb: Use safe window path when VRR TG is used | 4a68c7516c57 |
| C | drm/i915/display: Ensure a non-zero safe window from PTL onwards | b201029ca695 |
| D | drm/i915/vrr: Disable DC balance by default | c034e8a46e4c |
| G | drm/i915/xe: Enable HPD polling later during system resume | 3eb3190a0a1f |
| H | drm/xe: Fix shrinker accounting double-subtraction on nested external pins | 83d5acca1f4f |
| I | drm/i915/display: Mask RO bits in gen9_write_dc_state() | 94c0b93dc2a5 |

Applied:

| # | patch | source | result |
|---|-------|--------|--------|
| 0001 | drm/i915/cx0: request TCSS power for the non-TC C20 PHY on PTL port B | patches-vrr-tcss/0005 | clean (git am -3) |
| 0002 | zenbook-duo-2026-linux: module parameter for the TCSS change | patches-vrr-tcss/0006 | clean (git am -3) |

## Compile test

Same procedure as 7.2 (Arch 7.2.9 config, bc shim, olddefconfig, modules_prepare, distro vmlinux as
BTF base, xe.ko with modpost fed the distro Module.symvers and -w); see ../7.2/NOTES.md.

Result: **success** (rc=0). Compiler warnings in the whole xe build: 0.
modpost reported 10 unresolved symbols (new 7.3 core exports such as drm_gpusvm_pages_valid,
ttm_resource_manager_set_dmem_region/_dmem_reclaim, drm_dp_tunnel_128b132b_*, perf_allow_cpu,
__drm_atomic_helper_{crtc,plane}_state_init, dma_fence_enable_signaling) that the 7.2.9
Module.symvers does not list; none is referenced by the patches. Logs: build-logs/.

sha256 (unstripped drivers/gpu/drm/xe/xe.ko in series-work/7.3):
22a9b310e4876a7aab26a0f2d21b7bc676f09a152a60c8cbb166a80aa7c45ff1
