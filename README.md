# One UI (Android 16, a15x port) for TECNO Spark 20 (KJ5)

Fully booting One UI 16 GSI port on the TECNO Spark 20 (KJ5, MT6768 / Transsion), fixed for this device.

## Status: boots & stable with One UI Home ✅

Each flashable image below has an increasing set of fixes. Use **FIXED-v10** (latest).

Flash & hardware-tested on rooted KJ5 (KernelSU, permissive boot, AVB/vbmeta disabled) — via fastboot or DSU.

1. **Zygote abort** — `Not allowlisted: /system/system_ext/framework/mediatek-common.jar`
   (bundled `system_ext` symlink vs. Android's fork fd-allowlist) → restored stock layout
   (`/system_ext` real dir).
2. **system_server vibrator crash** — `libvibratorservice.so` deref'd Samsung's SEH
   vibrator HAL without null-checks (19 call sites patched to fail safely).
3. **Follow-on crash** — `AStatus_getExceptionCode(NULL)` in `libbinder_ndk.so` →
   null-safe fix.
4. **SetupWizard region screen stuck** — removed Samsung SecSetupWizard
   (`ro.setupwizard.mode=DISABLED`).
5. **SystemUI crash loop on any action** — `SecurityException` on OneUI Home's
   launcher settings provider (their SystemUI build lacks the uses-permission).
   Fixed **without touching signed apps** (see report for why re-signing is fatal):
   patched framework `services.jar` to allow the launcher settings provider.
6. **Launcher black screen** — reverted any signature change on TouchWizHome; a
   Samsung-signed app must keep Samsung's certificate or hidden-API calls die.
   Also removed crash-spamming `SamsungDeviceHealthManagerService` + `SohService`.

Full write-up with disassembly notes and per-version details:
👉 **[FIX_REPORT.md](FIX_REPORT.md)**

## Install

Download both parts of the v10 image from [Releases](../../releases), join and flash:

```bash
cat oneuiandroid16system-FIXED-v10.img.gz.part-* > oneuiandroid16system-FIXED-v10.img.gz
gunzip oneuiandroid16system-FIXED-v10.img.gz        # -> raw system image
fastboot flash system oneuiandroid16system-FIXED-v10.img
```

Fresh userdata/DSU slot recommended. First boot is slower than usual (SystemUI/services
re-dexopt after one-time rebuilds). If any app complains about provisioning after boot:

```bash
settings put global device_provisioned 1
settings put secure user_setup_complete 1
```

## Known quirks

- `mcDriverDaemon` (Trustonic TEE vendor daemon) logs a non-fatal abort — harmless.
- `nvram_daemon` logs a non-fatal SIGSEGV — harmless.
- Samsung Messages may show one background crash popup related to missing Samsung AI
  (scs.ai.search) services — cosmetic only on this device.

## What NOT to do when porting this to other devices

- Never re-sign SystemUI — Android assigns `android.uid.systemui` to platform-signed
  packages only (a resigned SystemUI is demoted to a normal uid and boot-loops).
- Never re-sign Samsung's launcher (TouchWizHome) — it loses the hidden-API exemption
  and crashes on `@UnsupportedAppUsage` blacklist members with NoSuchMethodError.
