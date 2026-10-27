# iPhone TestFlight preparation

## Release decision

Prepare a TestFlight beta first. The intended US App Store launch price is **US$0.99, one-time purchase**. No subscription or in-app purchase is planned. App Store pricing has not been configured, and this document does not announce availability.

## Current build

- Scheme: `WatermelonFin iOS`
- Bundle identifier: `org.chenacademy.watermelonfin`
- Version/build: `1.0.0 (8)`; verify the next unused build number in App Store Connect before uploading.
- Minimum iOS/iPadOS: 17.5; supports both iPhone and iPad
- Automated simulator validation: seven tests passed on each of CS iPhone Duo and iPad Pro 13-inch (M5). See `iphone-verification.md` for actual runtime coverage and remaining tests.
- Developer team: Wei Chen (`GP22YF7BL7`), using automatic signing for iOS, tvOS, and Top Shelf.
- Release archive check: optimized unsigned archive succeeded on Xcode 27.1 after updating Transmission to 2.12.3 and Engine to 2.12.2. Distribution signing and TestFlight upload remain outstanding.
- Existing App Store Connect app: WatermelonFin, Apple ID `6789271807`, bundle ID `org.chenacademy.watermelonfin`. iOS was added alongside tvOS for one app record. The previous tvOS build is 1.0.0 (6); new uploads use build 8.

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

The iOS build 8 signed archive succeeded. The tvOS build 8 unsigned archive succeeded; distribution signing happens during export because the team has no registered Apple TV development device. Xcode may warn that MPVKit has no matching dSYM; this affects symbolication of that framework and is separate from Apple processing acceptance. New TestFlight availability must be checked after processing.
