# Contributing to WatermelonFin

> Thank you for your interest in contributing to WatermelonFin. This page and its children describe the ways you can contribute, as well as some of our policies. This should help guide you through your first Issue or PR.

> Even if you can't contribute code, you can still help WatermelonFin. The two main things you can help with are testing and creating issues. Contributing to code, documentation, and other non-code components are all outlined in the sections below.

## Setup

Fork the WatermelonFin repo and install the necessary dependencies with a current Xcode release supporting the project’s SDK requirements:

```bash
# install Carthage, SwiftFormat, and SwiftGen with homebrew
$ brew install carthage swiftformat swiftgen

# install or update dependencies
$ carthage update --use-xcframeworks
```

In the event that all of the Swift Packages cannot be installed, clean the Swift Packages cache or close and reopen Xcode to restart the process.

### Xcode Config

Use an `xcconfig` file to easily set and keep your development team and a custom bundle identifier for local development to your devices.
The checked-in Xcode project inherits the development team from this local file so personal team IDs stay out of source control.

Create the `XcodeConfig/DevelopmentTeam.xcconfig` file [through Xcode](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project) or locally with the following values:

```
DEVELOPMENT_TEAM = ""
PRODUCT_BUNDLE_IDENTIFIER = org.chenacademy.watermelonfin
```

Update the `DEVELOPMENT_TEAM` value with your Team ID. This can be found by:
- Setting the `Development Team` value under the `Signing & Capabilities` tab in Xcode and get the value from source control. Make sure to discard this change.
- Logging into your Apple Developer account and [view your membership details](https://developer.apple.com/account/#/membership). It will be listed next to `Team ID`.

You can change the `PRODUCT_BUNDLE_IDENTIFIER` value to have multiple builds of WatermelonFin on your devices or for provisioning purposes.

`DevelopmentTeam.xcconfig` is already added to the `.gitignore`.

## Git Flow

WatermelonFin follows a focused pull request workflow: keep changes scoped, include local validation output, and explain user-facing impact.

If a Pull Request relates to an Issue, mention the issue correctly in the PR description.

[SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) are used for local checks. `swiftformat .` can be run in the project directory or install SwiftFormat's Xcode extension.

### Before Opening a Pull Request

GitHub Actions run automatically for pull requests and pushes to `main`, so please run the same checks locally before opening a PR. This keeps CI minutes focused on confirmation instead of catching issues that can be found on your machine first.

Install the command line tools if needed:

```bash
brew install swiftlint swiftformat swiftgen
```

Run the pre-PR checks from the repository root:

```bash
swift Scripts/Checks/ValidateATSConfiguration.swift
bash Scripts/Checks/run-reliability-checks.sh
python3 Scripts/Checks/check-swiftlint-regressions.py origin/main
swiftformat . --lint --config ".swiftformat"
xcodebuild build \
  -project WatermelonFin.xcodeproj \
  -scheme "WatermelonFin tvOS" \
  -destination "generic/platform=tvOS Simulator" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

If a local SDK or dependency issue prevents the build from running, note that in the PR description and include the checks that did run.

The following must pass in order for a PR to be merged:
- automated builds and tests for every supported platform must succeed
- developer account cannot be attached
- SwiftFormat linting check must pass. If this does not pass, you may need to update your version of `swiftformat`
- new strings that are not part of an experimental feature must be localized
- label(s) are attached, if applicable

Labeling PRs with `enhancement`, `bug`, or `crash` will allow the PR to be tracked in GitHub's [automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes). Small fixes (like minor UI adjustments) or non-user facing issues (like developer project clean up) can also have the `ignore-for-release` label because they may not be important to include in the release notes.

### Documentation
Documentation for advanced or complex features and other implementation reasoning is encouraged so that future developers may have insights and a better understand of the application. `// MARK:` comments are encouraged for organization, maintainability, and ease of navigation in Xcode's Minimap.

## Architecture

WatermelonFin is developed using SwiftUI with shared backend code and tvOS-specific views.

Playback is done with [MPV](https://mpv.io) for its broad codec and subtitle support. Becoming familiar with libmpv and MPVKit will be necessary for video playback development and debugging.

## Design

While there are no design guidelines for UI/UX features, WatermelonFin has the goal to use native SwiftUI/UIKit components while adhering to a Jellyfin theme. If a feature creates new UI/UX components, it may receive feedback during the PR process or may be re-designed later on.

User customizable UI/UX features are welcome and intended, however not all customization may be accepted for code maintainability and to also establish a distinct WatermelonFin design. Taking inspiration, but not always copying, from other applications is encouraged.

## App Icons

Ideas for new icons and minor tweaks to existing icons can be presented however may not be accepted. Overall, app icons must follow these rules:

- Must feature the Jellyfin logo.
- Must be for general usage (i.e: holiday, hacker theme). Ideas for individual preferences or logos will not be accepted.
- Must be unique. (i.e: cannot have two blue icons just with different gradients)

## New Features

If you would like to develop a new feature, create a Feature Request to discuss the feature's possibility and implementation. Leave a comment when you start working to prevent conflicts. If the implementation of a feature is large or complex, creating a Draft PR is acceptable to surface progress and to receive feedback.

## Other Code Work

Other code work like bug fixes, issues with `Developer` tags, localizations, and accessibility efforts are welcome to be picked up at any time.

If you notice undesirable behavior, would like to make a UI/UX tweak, or have a question about implementations, create an issue or ask in the iOS Matrix/Discord channel for insights.

## Intended Behaviors Due to Technical Limitations

The following behaviors are intended due to current technical limitations with the active player backend:

- Audio delay may occur when starting playback and un-pausing on some media or output configurations

The SwiftLint gate rejects newly introduced errors against the base revision. Existing violations remain visible as a backlog; SwiftFormat checks all source files.
