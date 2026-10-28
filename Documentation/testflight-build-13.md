# Build 13: manual server setup while discovery is deferred

Status on October 28, 2026: code prepared; **not uploaded to TestFlight**.

## Scope

- Shared iPhone, iPad and tvOS server setup opens the address field directly.
- Broadcast discovery is disabled at the UI, recovery and UDP transport boundaries.
- No subnet/IP scan is implemented. Recovery only tries previously saved addresses and verifies the server ID before switching.
- Bare addresses retain the default 8096 port behavior. Tailscale remains optional and can be added later.
- English, Simplified Chinese and Traditional Chinese copy describes current behavior; local-network permission remains necessary for direct LAN connections.
- The existing launch animation and explicit Add Server entry remain unchanged.

## Validation

- `bash Scripts/Checks/validate-local.sh --quick`: passed (playback, artwork, paging, PIN, address/identity policy, both ATS configurations and whitespace checks).
- Swift frontend parse of modified Swift files: passed; this is not full type checking or a successful app build.
- Independent code review: no important logic regressions; identified copy gaps were corrected.
- Updated iPhone/iPad UI regression asserts direct entry, no search controls, and preservation after background/rotation. Added tvOS view-model regression for disabled search. These tests have **not run successfully** in this session.
- Simulator access failed with CoreSimulatorService connection/permission errors. Signed archive attempts failed during dependency resolution because SwiftPM manifest diagnostics still target a protected user cache, even with a writable package copy and `-packageCachePath`.
- This session has no Xcode/browser UI control available. No build-13 archive, upload, processing acceptance or tester assignment is claimed.

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
