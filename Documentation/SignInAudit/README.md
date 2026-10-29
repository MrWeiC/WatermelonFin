# First-run and sign-in UI audit

The sign-in flow now has one red primary action, a readable secondary Quick Connect action, persistent field labels, and deliberate keyboard focus. The audit also caught and repaired broken error recovery and password handling, beyond the visual defects in the original screenshot.

Open [the before/after gallery](index.html) for full-resolution screenshots. The [implementation plan](../../docs/superpowers/plans/2026-10-28-sign-in-audit.md) and [independent review](review.md) record the approach and review boundaries.

## UI/UX Pro Max review

Consulted native-mobile media-player design-system, SwiftUI form/keyboard/accessibility, and UX form-label/touch-target/contrast/error-recovery guidance. Applied: one primary action, persistent labels, at least 44-point password-toggle target, clear cancellation and retry, readable enabled-action contrast, and layouts that adapt to keyboard, Dynamic Type, and iPad. Existing red branding and system typography remain.

| Before | After | Evidence |
|---|---|---|
| Custom fills stacked over native button containers | One background per action; consistent corners and primary/secondary hierarchy | 03 initial sign-in, 04 keyboard |
| Filled fields lose their placeholder labels | Persistent Username and Password labels | 04 keyboard |
| Keyboard opens before choosing a sign-in method | Initial screen shows account and Quick Connect choices | 03 initial sign-in |
| Back and Close compete in pushed navigation | System Back for pushed sign-in; Close for standalone presentation | 03 initial sign-in |
| Long explanatory copy crowds the form | Server name and one concise account instruction | 03, 15 language variants |
| iPad form stretches across the display | Centered form capped at 640 points | iPad 02–04 |
| Large-text Quick Connect can overflow | Scrollable instructions; six-digit code fits in landscape | 16–18 accessibility layouts |
| Security sheet has no explicit dismissal | Accessible Close action | 06 security |
| Login/server errors leave controls loading or disabled | Error dismissal restores editing and retry | 07–09 recovery |
| Quick Connect Retry cannot restart SDK error state and stretches vertically | Compact native action; cancel old subscription, reset SDK, and restart with continuation retained | 13–14 retry to Home; button-height assertion |
| Passwords lose surrounding spaces | Exact password preserved | Automated spaced-password sign-in |
| Reveal replaces the secure field and interrupts editing | Stable native field preserves focus, text, selection and Next/Go behavior | Automated reveal/edit/re-mask and 19–20 cancellation |

## Reproduce

Start `python3 Scripts/UITests/jellyfin_fixture.py`, then run `bash Scripts/UITests/run-sign-in-audit.sh <simulator-udid> <new-result-directory>`. Keep simulator signing enabled: successful authentication uses the real Keychain, which rejects writes from an unsigned host. The fixture binds only loopback, serves fake credentials and never forwards requests. Each launch uses a DEBUG-only in-memory store; production storage is unchanged.

The runner captures the UI suite. Final verification additionally runs the complete iOS scheme and affected TV scheme. `export_screenshots.py` extracts named XCTest attachments; `build_gallery.py Documentation/SignInAudit` rebuilds the comparison page.

## Evidence and scope

Baseline revision: `76e16fe1` (build 13 source). Six matched states per device: account selection, server entry, initial sign-in, keyboard-open sign-in, Quick Connect code, and security. Baseline account-selection data may show accumulated fixture servers; updated tests isolate the store, so that data difference is not a UI change. An early incomplete-fixture capture was discarded; included baselines wait for valid public-user data and reject unexpected alerts.

Coverage includes English, Simplified Chinese, Traditional Chinese, maximum accessibility text, landscape Quick Connect, server failure/cancellation, login failure/retry/success, Quick Connect failure/retry/success, unavailable Quick Connect, empty public users, password visibility/editing/whitespace, keyboard Next/Go, and cancellation without late navigation.

The iPhone runs with a dark OS appearance and iPad with light OS appearance. The signed-out app intentionally remains dark via its existing Info.plist setting; this audit does not introduce a global theme change. Screenshot coverage is for this first-run/sign-in flow, not every screen in the application.

The successful password-login screenshot may include the operating system’s Save Password prompt after reaching Home; this is expected credential-manager behavior. Password reveal no longer triggers that prompt mid-edit. Landscape evidence uses full-screen XCTest capture because app-only capture cropped rotated pixels.

Simulator automation uses the real app navigation and network stack against a controlled Jellyfin fixture. It does not establish physical-device VoiceOver/password-manager behavior, every real Jellyfin deployment, duplicate-account replacement, saved-server reconnect, or unrelated uses of the shared button style. TV regression coverage is functional; this report does not claim a new TV screenshot audit.

## Final verification

| Check | Result | Evidence |
|---|---|---|
| iPhone 13 Pro Max, iOS 26.5 — complete scheme | 17 passed, 0 failed | [Summary](results/iphone.json) |
| iPad Pro 13-inch M5, iPadOS 27 — complete scheme | 17 passed, 0 failed | [Summary](results/ipad.json) |
| Final Quick Connect error UI and retry → Home | 1 passed per device | [iPhone](results/iphone-retry.json), [iPad](results/ipad-retry.json) |
| Full-screen iPhone language/layout recapture | 1 passed | [Summary](results/iphone-layout-recapture.json) |
| Apple TV 4K, tvOS 26.5 | 145 passed, 0 failed, 1 skipped (live-server credentials unavailable) | [Summary](results/tv.json) |
| Repository quick checks | Passed: localization, format arguments, permissions, playback reliability, Top Shelf, paging, PIN, server identity, ATS | `bash Scripts/Checks/validate-local.sh --quick` |
| Independent review | Accepted password-preservation and accessibility-label findings resolved; follow-up editing test caught and verified a native-field regression | [Review](review.md) |

The gallery contains 12 baseline screenshots and 44 updated screenshots (22 named states per mobile device). The complete scheme runs precede the final isolated Quick Connect error-presentation adjustment; targeted recovery tests on both devices and the TV suite were rerun afterward. Source bundles are `/tmp/watermelon-audit-{phone,ipad}-final-v3.xcresult`, `/tmp/watermelon-audit-phone-screen-v4.xcresult`, `/tmp/watermelon-audit-{phone,ipad}-retry-v6.xcresult`, and `/tmp/watermelon-audit-tv-final-v6.xcresult`. Saved JSON summaries and screenshot manifests retain the evidence after those temporary bundles are removed.

No TestFlight upload or public release is part of this PR.
