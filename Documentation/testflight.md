# iPhone TestFlight preparation

## Release decision

Prepare a TestFlight beta first. The intended US App Store launch price is **US$0.99, one-time purchase**. No subscription or in-app purchase is planned. App Store pricing has not been configured, and this document does not announce availability.

## Current build

- Scheme: `WatermelonFin iOS`
- Bundle identifier: `org.chenacademy.watermelonfin`
- Version/build: `1.0.0 (10)` for iPhone/iPad; tvOS is `1.0.0 (9)`. Verify the next unused build number in App Store Connect before uploading.
- Minimum iOS/iPadOS: 17.5; supports both iPhone and iPad
- Automated simulator validation: seven tests passed on each of CS iPhone Duo and iPad Pro 13-inch (M5). See `iphone-verification.md` for actual runtime coverage and remaining tests.
- Developer team: Wei Chen (`GP22YF7BL7`), using automatic signing for iOS and Debug builds; tvOS/Top Shelf Release use the manual distribution profiles listed below.
- Release archive check: optimized unsigned archive succeeded on Xcode 27.1 after updating Transmission to 2.12.3 and Engine to 2.12.2. Signed iOS build 10 and tvOS build 9 archives were uploaded through Xcode and completed Apple processing on October 27, 2026. Both are assigned to the existing Internal Tester group (one tester).
- Existing App Store Connect app: WatermelonFin, Apple ID `6789271807`, bundle ID `org.chenacademy.watermelonfin`. iOS was added alongside tvOS for one app record. The previous tvOS build was 1.0.0 (6); current internal builds are iOS 10 and tvOS 9.

## Upload prerequisites

1. Use the existing WatermelonFin app record for both iOS and tvOS. The app targets now share its bundle identifier; iPhone and iPad are supported by the same iOS build. Confirm the next unused build number before any subsequent upload.
2. Resolve the linked player library's distribution requirements. The lockfile pins `streamyfin/MPVKit` at `0.40.0-av`, revision `d3d341129f77a5eb5251bd8c68fd1243a0ca1c73`; both app targets link the `MPVKit-GPL` product. Its README explicitly describes GPL v3 components, while its LICENSE file contains LGPL text. A root MPL notice alone is not a complete dependency review. Confirm applicable source, notice, and distribution requirements for the actual binary before TestFlight delivery; do not silently replace or remove playback features.
3. Confirm privacy disclosures, privacy manifests for the actual build, encryption/export answers, support contact, and beta feedback email. The current encryption plist answer is inherited configuration, not a newly completed export assessment.
4. In Xcode, select the correct development team and a generic iOS device, then Product → Archive. Validate the signed archive in Organizer. An unsigned local archive is a build check, not an uploadable TestFlight build.
5. Upload to App Store Connect, wait for processing, complete any required information, then add the build to an internal testing group. Start with the account holder; do not invite other people without explicit instructions.
6. Test on a physical iPhone. External testing can follow after the internal build works and any required beta review is complete. Do not publish a public invitation link yet.

Apple documentation: [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [Internal testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/), [External testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

## What to Test — 简体中文

WatermelonFin iPhone 首个测试版：请连接自己的 Jellyfin 服务器，测试登录、片库浏览、搜索、影片和剧集播放，以及返回后台后继续使用。

重点检查：拖动进度条后是否停留在目标位置；音轨和字幕选择；下一集连续播放；播放列表中的重复条目；PIN／Face ID；播放器出错后的恢复；横竖屏切换。折叠设备还请检查展开、半展开和折叠时的布局与播放连续性。

反馈时请提供设备型号、iOS 版本、App 版本／构建号、复现步骤和错误提示。日志或截图中请删除服务器密码、访问令牌及个人媒体信息。

需要自己的 Jellyfin 服务器和账号。本 App 不提供媒体内容。

## What to Test — English

First iPhone beta of WatermelonFin. Connect your own Jellyfin server and test sign-in, libraries, search, movie and episode playback, and returning from the background.

Focus on seeking that stays at the selected position, audio/subtitle selection, next-episode autoplay, duplicate playlist entries, PIN/Face ID, playback-error recovery, and rotation. On folding devices, check open, partially open, and closed layouts and playback continuity.

Include your device, iOS version, app version/build, reproduction steps, and error message with feedback. Remove passwords, access tokens, and personal media information from logs and screenshots.

A Jellyfin server and account are required. This app does not provide media content.

## Price setup after beta validation

In App Store Connect, select the United States base storefront and the available USD 0.99 price point. Review Apple's generated prices for other storefronts separately. The account holder must complete any required paid-app agreement, tax, or banking steps personally. Keep the app unreleased until testing and submission preparation are complete.

## Upload validation

iOS build 7 uploaded successfully from Xcode but Apple processing rejected it with 90208: the generated MPVKit framework plist advertised iOS 12.0 while its linked binary required 17.5. Both app targets now run `Scripts/Distribution/NormalizeMPVKitMinimumOS.sh`, which derives MinimumOSVersion from the embedded Mach-O binary and re-signs the framework when signing is enabled. Build 8 archives for iOS and tvOS were verified to declare and require 17.5.

The iOS build 8 signed archive succeeded. The tvOS build 8 unsigned archive succeeded; the later tvOS build 9 signed archive used the approved local distribution certificate and manual App Store profiles. Xcode may warn that MPVKit has no matching dSYM; this affects symbolication of that framework and is separate from Apple processing acceptance. Apple processing completed for iOS 9, iOS 10, and tvOS 9; the current builds are assigned to Internal Tester. External testing and public release have not been started.

iOS build 8 passed the framework minimum-OS check but Apple processing returned 90683 for a missing camera purpose string referenced by the player dependency. Build 9 includes camera and microphone purpose strings that accurately state the app does not capture photos/video or record audio. The app does not request those permissions in its playback flows.

The owner authorized creation of a local Apple Distribution certificate and two tvOS App Store profiles. TV Release builds use manual signing with `WatermelonFin tvOS App Store Local 2026` and `WatermelonFin TopShelf App Store Local 2026`; Debug remains automatic. Install the corresponding profiles and certificate before a signed TV archive. No private key or provisioning profile is committed.

## Branding verification — build 10

iOS build 9 accidentally retained the legacy blue app icon. Build 10 uses the approved red watermelon artwork from `Scripts/Branding/Sources/watermelonfin-original.png`. The branding generator now emits an opaque 1024-pixel iOS icon and synchronizes the existing red wordmark assets; `--ios-only` regenerates just those iOS assets.

Verified the actual build 10 archive: its iPhone and iPad app-icon PNGs contain the red watermelon, and `Assets.car` contains `watermelonfin-logo` at 1x, 2x, and 3x. The logo is compiled into the asset catalog rather than shipped as a loose PNG. The running CS iPhone Duo simulator also displays the red watermelon wordmark on the login screen. Apple processing shows Complete and the existing internal group has build 10.
