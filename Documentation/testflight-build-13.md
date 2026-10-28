# Build 13: manual server setup while discovery is deferred

Status on October 28, 2026: startup-animation PR #37 merged. Localization release preparation is in progress; **not uploaded to TestFlight**.

## Scope

- Shared iPhone, iPad and tvOS server setup opens the address field directly.
- Broadcast discovery is disabled at the UI, recovery and UDP transport boundaries.
- No subnet/IP scan is implemented. Recovery only tries previously saved addresses and verifies the server ID before switching.
- Bare addresses retain the default 8096 port behavior. Tailscale remains optional and can be added later.
- English, Simplified Chinese and Traditional Chinese copy describes current behavior; local-network permission remains necessary for direct LAN connections.
- The crystal-watermelon launch video runs locally on iPhone, iPad, and tvOS. The explicit Add Server entry remains.
- The app follows the device language, with English as the development fallback. English, Simplified Chinese, and Traditional Chinese include all source catalog keys and permission descriptions.
- Legacy translations with invalid format arguments or empty values fall back to English. Other languages remain partially translated.
- Shared account, server, and playback errors now use localized strings; Jellyfin/server-provided messages and media names retain their original language.

## Validation — October 28 release preparation

- `python3 Scripts/Checks/ValidateLocalizations.py`: all 996 English source keys are present in both Chinese catalogs; permission descriptions and playlist strings are covered; printf arguments match across all 48 bundled languages.
- `bash Scripts/Checks/validate-local.sh --quick`: passed.
- iPhone and iPad simulator suites: eight tests passed on each, including launches in English, Simplified Chinese, Traditional Chinese, and an unsupported language that falls back to English.
- Signed tvOS simulator suite: 145 passed, one skipped (live Jellyfin credentials not supplied), zero failures. The Chinese-copy suite now explicitly selects Chinese. Its Keychain integration test requires a signed simulator host.
- Independent review identified default-language settings and inaccurate Chinese labels; these were corrected.
- Translation coverage and test results do not certify every screen's layout or third-party/server-provided messages. Physical-device visual checks remain useful.
- A pre-localization iOS build-13 archive succeeded locally but was not uploaded. Release archives must be rebuilt from the final localization commit.

## Finish release from an authorized Xcode session

1. Check App Store Connect for an unused build number; 13 is the prepared candidate for both apps and Top Shelf.
2. Run `bash Scripts/Checks/validate-local.sh --all`, including iPhone, iPad and tvOS. Verify manual entry, local-network prompt localization, same-server address switching and rejection of a different server ID. Do not put live test credentials in source or logs.
3. Review and merge the change after full checks pass.
4. Archive and distribute both `WatermelonFin iOS` (covers iPhone/iPad) and `WatermelonFin tvOS` using existing signing settings.
5. Verify Apple processing is Complete and both builds are available to the existing Internal Tester group. Upload success alone is insufficient.

Do not enable `ServerDiscovery.isEnabled` until multicast approval, provisioning updates, correct signed entitlements and physical-device validation are complete. Approval alone does not change installed builds.

## What to test

服务器添加现直接显示地址输入，暂时关闭自动发现。支持默认 8096 端口和可选备用地址。请测试手动添加、登录、已有地址切换、中文权限提示，以及启动动画不被打断。

Server setup now opens address entry directly while automatic discovery is deferred. Default port 8096 and optional alternate addresses remain supported. Test manual setup, sign-in, saved-address recovery, localized local-network permission prompts and uninterrupted launch animation.
