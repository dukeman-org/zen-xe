# 7.0 series (base v7.0.14)

Base: v7.0.14 (458c6079fc1d), stable/linux-7.0.y tip (branch ended 2026-06-27). Worktree: series-work/7.0.

| # | patch | upstream | result |
|---|-------|----------|--------|
| 0001 | drm/i915/dsb: shift delayed-vblank DSL wait start by one scanline | f7140c7cef30 | clean (cherry-pick -x); the VRR WAIT_DSL_OUT(safe_window_start, vmin_safe_window_end) path exists in 7.0.14's intel_dsb_wait_for_delayed_vblank() |
| 0002 | drm/i915/dsb: Use safe window path when VRR TG is used | 4a68c7516c57 | resolved: dsb_chicken() in 7.0.14 predates the PSR `DSB_SKIP_WAITS_EN`/`chicken |=` form (upstream context). Kept 7.0's `return`-style body and only swapped the predicate pre_commit_is_vrr_active() -> pre_commit_use_safe_window(). The other two hunks (intel_dsb_vblank_evade, intel_dsb_wait_for_delayed_vblank) and the new helper applied cleanly; the +/- lines of the resulting commit are identical to upstream. intel_vrr_always_use_vrr_tg() exists in 7.0.14, so the always-on VRR TG bug is present. |
| 0003 | drm/i915/display: Ensure a non-zero safe window from PTL onwards | b201029ca695 | clean (intel_crtc_set_context_latency() present; DISPLAY_VER >= 30 check kept as upstream) |
| 0004 | drm/i915/vrr: Disable DC balance by default | c034e8a46e4c | clean. Fixes 555819270707 which is an ancestor; no 7.0.y sublevel has the fix (7.0.y ended before it was written), so no version constraint in `series`. |
| 0005 | drm/i915/cx0: request TCSS power for the non-TC C20 PHY on PTL port B | patches-vrr-tcss/0005 | applied cleanly with git am -3 but did not compile: `intel_reg_t` does not exist before 7.2 (typedef added by e892c68bba23). Resolved by using `i915_reg_t` for the local in intel_tc_request_tcss_power(); otherwise identical. |
| 0006 | zenbook-duo-2026-linux: module parameter for the TCSS change | patches-vrr-tcss/0006 | clean (git am -3) |
| 0007 | drm/i915/xe: Enable HPD polling later during system resume | 3eb3190a0a1f | clean (xe_display_pm_resume() has the same poll_enable-before-enable_user_access order) |
| 0008 | drm/xe: Fix shrinker accounting double-subtraction on nested external pins | 83d5acca1f4f | clean (Fixes: 00c8efc3180f is an ancestor; xe_bo_pin_external() in 7.0.14 does the unconditional ttm_bo_pin + xe_ttm_tt_account_subtract on every pin, i.e. the bug exists). Resulting +/- lines identical to upstream. |
| 0009 | drm/i915/display: Mask RO bits in gen9_write_dc_state() | 94c0b93dc2a5 | resolved: same intel_display_regs.h conflict as on 7.1/7.2; kept the tree's DC_STATE_EN defines, added only DC_STATE_EN_CSR_MASK_CMTG_1 (bit 11) and _CMTG_0 (bit 10). |

## Compile test

Same procedure as 7.2 (Arch 7.2.9 config, bc shim, olddefconfig, modules_prepare, distro vmlinux as
BTF base, xe.ko with modpost fed the distro Module.symvers and -w); see ../7.2/NOTES.md.

Result: **success** (rc=0). Compiler warnings in the whole xe build: 0.
modpost reported 10 unresolved symbols (drm_atomic_state_*, drm_buddy_*, dma_buf_move_notify,
hugetlb_optimize_vmemmap_key): core exports of 7.0 that the 7.2.9 Module.symvers does not list
(export drift between 7.0 and 7.2); none is referenced by the patches. Logs: build-logs/.

sha256 (unstripped drivers/gpu/drm/xe/xe.ko in series-work/7.0):
94aab73e5ae4ba615d247dda830e8a439e9e451a73d61e6116a42cad05a7325b
