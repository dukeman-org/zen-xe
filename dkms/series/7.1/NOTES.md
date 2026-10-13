# 7.1 series (base v7.1.13)

Base: v7.1.13 (81d3924095fd), stable/linux-7.1.y tip at build time. Worktree: series-work/7.1.

| # | patch | upstream | result |
|---|-------|----------|--------|
| 0001 | drm/i915/dsb: shift delayed-vblank DSL wait start by one scanline | f7140c7cef30 | clean (cherry-pick -x) |
| 0002 | drm/i915/dsb: Use safe window path when VRR TG is used | 4a68c7516c57 | clean |
| 0003 | drm/i915/display: Ensure a non-zero safe window from PTL onwards | b201029ca695 | clean (DISPLAY_VER >= 30 check kept as upstream) |
| 0004 | drm/i915/vrr: Disable DC balance by default | c034e8a46e4c | clean. Not in any 7.1.y sublevel (7.1.13 is the branch tip and lacks it), so no version constraint in `series`. |
| 0005 | drm/i915/cx0: request TCSS power for the non-TC C20 PHY on PTL port B | patches-vrr-tcss/0005 | applied cleanly with git am -3 but did not compile: `intel_reg_t` does not exist before 7.2 (typedef added by e892c68bba23 in v7.2). Resolved by using `i915_reg_t` for the local in intel_tc_request_tcss_power(); otherwise identical. |
| 0006 | zenbook-duo-2026-linux: module parameter for the TCSS change | patches-vrr-tcss/0006 | clean (git am -3) |
| 0007 | drm/i915/xe: Enable HPD polling later during system resume | 3eb3190a0a1f | clean |
| 0008 | drm/xe: Fix shrinker accounting double-subtraction on nested external pins | 83d5acca1f4f | clean (Fixes: 00c8efc3180f is an ancestor; unconditional account_subtract in xe_bo_pin_external() present) |
| 0009 | drm/i915/display: Mask RO bits in gen9_write_dc_state() | 94c0b93dc2a5 | resolved: same intel_display_regs.h conflict as on 7.2; kept the tree's DC_STATE_EN defines, added only DC_STATE_EN_CSR_MASK_CMTG_1 (bit 11) and _CMTG_0 (bit 10). |

Bug-presence check: all touched code paths exist in v7.1.13 (same shape as v7.2.x for every file).

## Compile test

Same procedure as 7.2 (Arch 7.2.9 config, bc shim, olddefconfig, modules_prepare, distro vmlinux as
BTF base, xe.ko with modpost fed the distro Module.symvers and -w); see ../7.2/NOTES.md.

Result: **success** (rc=0). Compiler warnings in the whole xe build: 0.
modpost reported 6 unresolved symbols, all drm core (`drm_atomic_state_alloc/_init/_clear/
_default_clear/_default_release`, `__drm_atomic_state_free`): they are exported by 7.1's drm.ko
but absent from the 7.2.9 Module.symvers used for the check (export drift between 7.1 and 7.2),
unrelated to the patches. Logs: build-logs/.

sha256 (unstripped drivers/gpu/drm/xe/xe.ko in series-work/7.1):
c3cde9cfa6e962c22c16352df2350f6241becd1d7e2697630930b76a6346f820
