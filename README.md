# One UI (Android 16, a15x port) for TECNO Spark 20 (KJ5)

Working One UI Android 16 GSI port on the TECNO Spark 20 (KJ5, MT6768/Transsion), fixed to boot on this device.

## Status: boots to launcher ✅

Flashed and tested on rooted KJ5 (KernelSU), permissive boot image, AVB/vbmeta disabled.
Three kernel-/userspace-level bootblockers from the a15x port were fixed inside the image:

1. **Zygote abort** — `Not allowlisted: /system/system_ext/framework/mediatek-common.jar`
   (bundled `system_ext` symlink vs. Android's fork fd-allowlist) → fixed by restoring the
   stock layout (`/system_ext` real dir).
2. **system_server vibrator crash** — `libvibratorservice.so` dereferenced Samsung's SEH
   vibrator HAL without null-checks (19 call sites patched to fail safely).
3. **Follow-on crash** — `AStatus_getExceptionCode(NULL)` in `libbinder_ndk.so` patched
   to return `EX_UNSUPPORTED_OPERATION`.
4. **SetupWizard region screen stuck** — Samsung's region list can't resolve on this
   device; SetupWizard is disabled (`ro.setupwizard.mode=DISABLED`, SecSetupWizard removed).

Full technical write-up (root causes, disassembly notes, guidance for other One UI ports):
👉 **[FIX_REPORT.md](FIX_REPORT.md)**

## Install

Download the parts of `oneuiandroid16system-FIXED-v4.img.gz` from the
[latest release](../../releases), join and flash:

```bash
cat oneuiandroid16system-FIXED-v4.img.gz.part* > oneuiandroid16system-FIXED-v4.img.gz
gunzip oneuiandroid16system-FIXED-v4.img.gz      # -> raw system image
fastboot flash system oneuiandroid16system-FIXED-v4.img
```

After first boot, if anything asks for provisioning:

```bash
settings put global device_provisioned 1
settings put secure user_setup_complete 1
```

## Known quirks

- First boot takes a while (fresh dexopt).
- `mcDriverDaemon` (Trustonic TEE, vendor) logs a non-fatal abort — harmless.
- `nvram_daemon` logs a non-fatal SIGSEGV — harmless.

Older fixed images (v1–v3) are also attached for reference/bisection.
