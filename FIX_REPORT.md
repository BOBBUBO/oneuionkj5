# One UI (Android 16, a15x port) bootloop on TECNO Spark 20 (KJ5) — Root Cause & Fix

> **Flash this:** `oneuiandroid16system-FIXED-v4.img.gz` (all three fixes below + setup-wizard skip).
> 🎉 v3 boots fully into One UI — remaining known issue it fixes: SetupWizard stuck on empty region list.

## Fixing status

| # | Bug | Fix |
|---|-----|-----|
| 1 | Zygote abort: `Not allowlisted: /system/system_ext/framework/mediatek-common.jar` | v1+: symlink swap (verified gone in test log) |
| 2 | system_server SIGSEGV in `libvibratorservice.so` — SEH HAL null deref | v2: 19 call sites short-circuited |
| 3 | Follow-on SIGSEGV: `AStatus_getExceptionCode(NULL)` in the "failure" path | v3: libbinder_ndk null-safe patch |
| 4 | SetupWizard stuck at "Select region" (empty country list on non-Samsung CSC) | v4: `ro.setupwizard.mode=DISABLED` + removed `SecSetupWizard_Global.apk` |



Notes from test log (after v2): boot got past PMS and died again at
`supportsHapticEngine+0xc8` → `HalResultFactory::fromFailedStatus(...)` →
`libbinder_ndk.so AStatus_getExceptionCode` null deref. The redirected failure
constructors expect a real AIDL status object, which the skipped SEH call never
produced (`[sp,#0x18] == NULL`).

## Crash #1 — zygote `Not allowlisted` (the original bootloop)

`high_level_crash.log` shows a bootloop at the **zygote → system_server fork**, with this abort repeated every few seconds:

```
F DEBUG   : Abort message: 'JNI FatalError called: (system_server) Not allowlisted (24): /system/system_ext/framework/mediatek-common.jar'
...
#06 ...  libandroid_runtime.so (FileDescriptorInfo::CreateFromFd(...))
#08 ...  libandroid_runtime.so (android::zygote::ForkCommon(...))
#09 ...  libandroid_runtime.so (android::com_android_internal_os_Zygote_nativeForkSystemServer(...))
```

Everything before it is noise (the `nvram_daemon` SIGSEGV is a separate, non-fatal vendor quirk; the bootanimation `window_type`/`mps_code.dat` warnings are normal on non-Samsung LCD devices).

## Root cause

1. This GSI **bundles the a15x `system_ext` inside the system image** and replaces the rootfs mountpoint with a symlink:
   ```
   /system_ext -> /system/system_ext    (symlink inside the GSI rootfs)
   /system/system_ext/                  (real directory with mediatek-*.jar)
   ```
2. The classpath fragment `/system/etc/classpaths/bootclasspath.pb` correctly references the jars through `/system_ext/framework/mediatek-{common,framework,ims-base}.jar` (the a15x paths), so ART loads them into zygote's boot classpath. That part worked.
3. **The failure is in the zygote fork security check.** When zygote forks `system_server`, Android's `fd_utils.cpp` (`FileDescriptorInfo::CreateFromFd`) requires every inherited file descriptor to be allowlisted. The allowlist check is done on the fd's **kernel-resolved real path**, and framework jars are only auto-allowed under two fixed prefixes:
   - `/system/framework/`
   - `/system_ext/framework/`
4. On the GSI boot, `/system_ext` is a *symlink*, so the kernel resolves the mediatek jars to `/system/system_ext/framework/...`. That string matches **neither** allowed prefix → `Not allowlisted` → `abort()` → zygote restarts → infinite bootloop.

   (This is also why the same boot works fine on SPF-flashed "real" a15x: there `/system_ext` is a genuine partition mountpoint, so the resolved path really is `/system_ext/framework/...`.)

   Note: stock KJ5 passes the same check because Transsion puts the mediatek jars **physically under `/system/framework/`** (verified on-device: stock `BOOTCLASSPATH` = `/system/framework/mediatek-common.jar:...`).

## Crash #2 — system_server SIGSEGV in the Samsung vibrator SEH extension

After fix #1, the boot proceeded through PackageManagerService, then crashed in a loop at:

```
DEBUG : signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0000000000000000
#00 libvibratorservice.so (android::vibrator::AidlHalWrapper::supportsHapticEngine()+60)
#01 libandroid_servers.so  (... HalController::doWithRetry<bool> ...)
#05 services.jar (com.android.server.vibrator.VibratorController$NativeWrapper.supportsHapticEngine)
#09 services.jar (com.android.server.vibrator.VibratorManagerService.<init>)
```

Cause: the a15x One UI `libvibratorservice.so` unconditionally calls `getSehHal()` — Samsung's custom "SEH" vibrator HAL extension (vendor.samsung.hardware.vibrator) — and dereferences the returned shared_ptr **without a null check**:

```
1a280: bl   getSehHal
1a284: ldr  x0, [sp, #0x8]     ; = SEH HAL binder (NULL on non-Samsung-SEH hardware)
1a288: sub  x1, x29, #0xc
1a28c: ldr  x8, [x0]           ; <-- SIGSEGV, x0 == 0
```

The KJ5 only has MTK's legacy `vibrator.default.so` / `vibrator.mt6768.so` HIDL passthrough modules, so the SEH extension never registers → null pointer, every boot, at `VibratorManagerService` start.

### Fix #2 applied (binary patch of `/system/lib64/libvibratorservice.so`)

All **19** callers of `getSehHal()` in the library share the same unchecked pattern.
Each site was patched so that after `bl getSehHal`, control jumps straight to that
function's existing `HalResult::failure()` construction path instead of dereferencing
the (always-null) SEH binder on this hardware. Effect: all Samsung SEH haptic features
report "unsupported" (returns default failure → treated as `false`/-1), basic vibration
via the MT6768 HAL keeps working, and the crash is impossible.

Verification: `objdump` re-disassembly of the patched `.so` shows every `bl getSehHal`
immediately followed by a branch to a valid failure-return sequence; no raw `ldr x8, [x0]`
remains on any SEH path.

### Fix #3 applied (v3) — `/system/lib64/libbinder_ndk.so`: null-safe `AStatus_getExceptionCode`

```
168e0:  cbz  x0, 0x169d4       ; null status -> trampoline
168e4:  ldr  w0, [x0]          ; original instruction (non-null path)
168e8:  b    0x168f0           ; original second instruction
0x169d4 (alignment padding): mov w0, #-7 ; ret    ; EX_UNSUPPORTED_OPERATION
```

With this, `HalResult::failure()` construction works exactly as designed for the
skipped SEH calls, `AStatus_delete(NULL)` is a no-op, and vibrator haptic features
gracefully report unsupported. The patch is globally safe: previously null input was
undefined behaviour (crash); now it returns a documented error code.

### Non-blocking note (seen in same log, no action taken)
`/vendor/bin/mcDriverDaemon` (Trustonic/Mobicore TEE driver, KJ5 stock vendor) aborts
once with `thread::join failed: Resource deadlock`. Vendor-side bug, appeared also
in the pre-fix log — not fatal to boot. If it becomes a problem it can be silenced by
a KernelSU module masking its service rc (or adding `disabled` to it).

## Fix #1 applied (already in v1/v2)

Swap the symlink direction so `/system_ext` is the **real directory** and compatibility links still work:

- removed `/system_ext -> /system/system_ext` symlink
- moved the real directory `/system/system_ext` → `/system_ext`
- replaced `/system/system_ext` with a symlink → `/system_ext` (identical to stock layout; keeps any absolute `/system/system_ext/...` references in a15x rc files / file_contexts valid)

Now the mediatek jars physically live under `/system_ext/framework/`, the fd path matches the allowlist prefix, and **no changes to `bootclasspath.pb`, the jars, or the prebuilt `boot-mediatek-*.art/.vdex/.oat` images were needed** — everything keeps validating by original paths.

## Crash #4 (UX, not a crash) — SetupWizard stuck on "Select region"

On v3 the device fully boots One UI but Samsung SetupWizard's country/region list is
empty (Samsung CSC region data doesn't map to this Transsion device), blocking setup.

### Fix #4 applied (v4)
- `/system/build.prop`: appended `ro.setupwizard.mode=DISABLED`
- Removed `/system/priv-app/SecSetupWizard_Global/SecSetupWizard_Global.apk`

Result: boot goes straight to the launcher, no setup wizard. If anything still wants
provisioning, after first boot run once via adb/root:
```
settings put global device_provisioned 1
settings put secure user_setup_complete 1
```
Language/region can then be changed normally in Settings.

Verified with `e2fsck -f`, images repacked:
- `oneuiandroid16system-FIXED-v4.img.gz` — **flash this** (fixes 1+2+3+4)
- `oneuiandroid16system-FIXED-v3.img.gz` — boots fully, SUW stuck on region
- `oneuiandroid16system-FIXED-v2.img.gz` — fixes 1+2
- `oneuiandroid16system-FIXED-v1.img.gz` — fix #1 only

Flash and test:
```
gunzip oneuiandroid16system-FIXED-v3.img.gz  # if you need raw
fastboot flash system oneuiandroid16system-FIXED-v3.img
```
Note: v2 boot progressed far past the original failure — PackageManagerService scanned all apps. The vibrator-crash chain is fully patched in v3 (no more null derefs anywhere on the SEH path). Expect the next boot to reach setup/launcher or surface the next (independent) HAL issue if any.
(The logine shows your boot image, permissive + vbmeta flags are already handled — this fix is orthogonal to that.)

## If it still fails → what to check next

- New abort similar to `Not allowlisted: /system/product/...` (product jars) → apply the **same symlink swap** to `/product` (currently `product -> /system/product`).
- ART boot-image mismatch (`No class space, no boot image...`/very slow JIT boot): means something else changed the jar*path* mapping; re-dexopt fixes itself on first boot on permissive builds — just give it time.
- If system_server now starts but crashes on Samsung/OneUI services IMEI/triple-cam networking, that's Transsion-vendor-lib territory (logcat `main`), separate from this bug.

## Lesson for other One UI ports (MTK Transsion targets like KJ5/Camon/Infinix)

The a15x "GSI" is *not* a standard treble system-only GSI — it depends on a bundled `system_ext` with MediaTek jars on the **boot classpath**. Any port of it onto a device whose boot/fstab doesn't mount a real `system_ext` partition over the rootfs symlink will hit this exact `Not allowlisted: /system/system_ext/framework/mediatek-*.jar` bootloop. Fix at the build step, not per-device:

- either ship `/system_ext` as a **real directory** in the image (what we did), or
- physically place the mediatek boot-classpath jars under `/system/framework/` and update `/system/etc/classpaths/bootclasspath.pb` accordingly (stock KJ5 layout — but then prebuilt `boot-mediatek-*` vdex/oat location records must also match, so directory-move is cleaner).

Rule of thumb: **jar paths reachable through symlinks fail zygote's fd allowlist**, because the allowlist checks the fully resolved `/proc/self/fd` target, and only raw `/system/framework/` and `/system_ext/framework/` prefixes are permitted.

### Tooling used (for repeat builds)
- `e2fsprogs` (`debugfs`, `e2fsck`) — offline ext4 inspection/repair
- loop-mount under rooted kernel (`su`, SELinux permissive) to edit the raw image
- AOSP source: `frameworks/base/core/jni/fd_utils.cpp` (allowlist logic), `ZygoteInit.java`
