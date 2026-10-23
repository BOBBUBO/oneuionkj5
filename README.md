# One UI (Android 16, a15x port) for TECNO Spark 20 (KJ5)

Fully booting One UI 16 GSI port on the TECNO Spark 20 (KJ5, MT6768 / Transsion), fixed for this device.

## Status: boots & stable with One UI Home ✅ — speaker and wired-headphone audio fixed

The latest release is **FIXED-v15** (release **v1.2**): speaker and wired-headphone
audio work. Bluetooth audio is not fixed yet. The v15 image adds the missing Samsung
policy file **and** the missing `audio_effects_sec.xml`; see
[FIX_REPORT.md](FIX_REPORT.md) for the evidence. The v4 KernelSU module's overlay did
**not** apply on the tested KSU/SUSFS setup, so use the v15 image, not the module.

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

Download both parts of the v15 image from [Releases](../../releases), join and flash:

```bash
cat oneuiandroid16system-FIXED-v15.img.gz.part-* > oneuiandroid16system-FIXED-v15.img.gz
gunzip oneuiandroid16system-FIXED-v15.img.gz        # -> raw system image
fastboot flash system oneuiandroid16system-FIXED-v15.img
```

Fresh userdata/DSU slot recommended. First boot is slower than usual (SystemUI/services
re-dexopt after one-time rebuilds). If any app complains about provisioning after boot:

```bash
settings put global device_provisioned 1
settings put secure user_setup_complete 1
```

## Known quirks

- Bluetooth audio does not work yet; speaker and wired headphones do.
- `mcDriverDaemon` (Trustonic TEE vendor daemon) logs a non-fatal abort — harmless.
- `nvram_daemon` logs a non-fatal SIGSEGV — harmless.
- Samsung Messages may show one background crash popup related to missing Samsung AI
  (scs.ai.search) services — cosmetic only on this device.

## What NOT to do when porting this to other devices

- Never re-sign SystemUI — Android assigns `android.uid.systemui` to platform-signed
  packages only (a resigned SystemUI is demoted to a normal uid and boot-loops).
- Never re-sign Samsung's launcher (TouchWizHome) — it loses the hidden-API exemption
  and crashes on `@UnsupportedAppUsage` blacklist members with NoSuchMethodError.

## v11 extra: brightness fix baked in

The vendor lights HAL on the KJ5 feeds the panel raw 0-255 values while the panel
wants 0-4095. The community `skeleton.sh` only fixes max brightness. v11 ships an
init service (`/system/etc/init/kj5_brightfix.rc` + `/system/bin/kj5-brightfix.sh`)
that rescales every brightness write linearly — the whole slider range is usable.
If you had the old `service.d` shadow script installed, remove it.

## Audio status (v12 → v15)

- **v12** shipped an empty `/system/etc/audio_effects.xml`; Samsung's parser rejected
  it (`Failed to load XML effect configuration`). Do not use v12.
- **v13** restored the stock a15x effects config and removed the vendor DTS effect
  through a KernelSU module. It did not restore sound: One UI's audioserver never
  loads `/vendor/etc/audio_policy_configuration.xml`. It only searches for Samsung's
  `audio_policy_configuration_sec.xml`, which the KJ5 vendor does not ship, then falls
  back to an empty default policy.
- **v14** adds `/system/etc/audio_policy_configuration_sec.xml` (the KJ5 AOSP policy
  with absolute `/vendor/etc/...` includes). Hardware test confirmed the policy fix:
  the speaker output opened and volume reached 1.0. But the first audio track still
  aborted `audioserver` with `AudioPolicyEffects: Failed to load XML effect
  configuration`.
- **v15** adds the missing `/system/etc/audio_effects_sec.xml` (the DTS-stripped KJ5
  vendor effects config). Samsung's loader looks for `audio_effects_sec.xml`, not the
  `audio_effects.xml` restored in v13, and treats a missing file as fatal on the first
  playback. **Hardware-tested:** speaker and wired headphones work; audioserver no
  longer aborts. Bluetooth audio remains unfixed.
- The v4 KernelSU module was tried on v14. Its `service.sh` ran, but the KSU/SUSFS
  file overlay did **not** apply: `/system/etc/audio_effects_sec.xml` and
  `/vendor/etc/audio_effects_sec.xml` were absent, and `/vendor/etc/audio_effects.xml`
  remained the stock 7235-byte file. The module is therefore diagnostics-only on this
  setup; use the v15 image, which has the file baked into `/system`.

Full technical evidence is in **[FIX_REPORT.md](FIX_REPORT.md)**.

## Release v1.2 artifacts

- `oneuiandroid16system-FIXED-v15.img.gz.part-00` — SHA-256
  `b91e1802f7a934f7f933f921add06d48a21007b7cb231c098dfb693d877275ae`
- `oneuiandroid16system-FIXED-v15.img.gz.part-01` — SHA-256
  `3eb68ed8135904833f2ba3836c1fd8d3f52db31b8cbe26bc241bbf2e3780d4d3`
- Joined `oneuiandroid16system-FIXED-v15.img.gz` — SHA-256
  `689b10672036801b7f07033d8cb14f6ae30cddf1c5c0e40b6f2ab6fba7ee1fd8`
- Raw image after `gunzip` — SHA-256
  `debd3227caf97dfc7f008477aa3ac1e72a630dd89e8ed6ed8e434cdce2d4d7c3`
