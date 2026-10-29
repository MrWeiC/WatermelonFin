# Sign-in flow audit and repair

> Execute in this chat with superpowers:executing-plans; use one independent review before the PR.

**Goal:** Make first-run and account sign-in clear and usable on iPhone/iPad, preserve TV interaction, and provide automated evidence and a before/after report.

**Architecture:** Exercise the real app through XCTest against a local, deterministic Jellyfin HTTP fixture. Keep screen changes in existing SwiftUI views. Capture the same states before and after repairs.

**Tech Stack:** SwiftUI, XCTest, Python standard-library HTTP server, Xcode simulators.

**Spec:** User's screenshot and explicit request to test the entire sign-in flow, fix findings, open a PR, and report before/after. UI/UX Pro Max review: one clear primary action, persistent field labels, 44-point targets, readable contrast, clear recovery, keyboard and Dynamic Type support. Preserve WatermelonFin red, SF Symbols, and system typography.

## Global Constraints

- Work only in this managed worktree; leave the user's original checkout untouched.
- Fake fixture credentials only. No public release or TestFlight upload in this task.
- English, Simplified Chinese, Traditional Chinese remain supported; follow device language.
- Capture evidence before claiming a fix. Automated layout assertions complement visual inspection.

## Review Focus

Navigation after server connection, cancellation during requests, duplicate/saved accounts, password handling, Quick Connect lifecycle, keyboard focus, accessibility sizing, iPad width, and conditional TV behavior. Do not infer whole-flow correctness from a single successful screenshot.

## Task 1 — Baseline and repeatable automation

- [x] Add `Scripts/UITests/jellyfin_fixture.py` with valid, empty, error, delayed, and Quick Connect scenarios.
- [x] Add `SignInFlowTests.swift` alongside `FirstRunTests.swift` with named screenshot attachments and real navigation assertions.
- [x] Run baseline on iPhone and iPad; export attachments into the audit evidence directory.
- [x] Record observed failures and screenshots, distinguishing fixture errors from product regressions.

## Task 2 — Repair observed flow defects

- [x] Fix nested button backgrounds and hierarchy; retain TV focus styling.
- [x] Address form labels, keyboard/focus, validation, loading/cancel/error recovery and Quick Connect usability based on baseline evidence.
- [x] Keep forms readable on iPad and at larger text sizes; update all three supported localizations for changed copy.
- [x] Run regression tests after each relevant fix; inspect screenshots rather than relying solely on assertions.

## Task 3 — Verification and comparison

- [x] Run full mobile tests on iPhone/iPad and affected TV suite; run repository quick checks.
- [x] Capture first run, server form/error/loading, account form/keyboard/error/loading, public users, security, Quick Connect/code/cancel, and successful sign-in return.
- [x] Include light/dark, Chinese variants/English, large text, and landscape coverage in the matrix.
- [x] Write `Documentation/SignInAudit/README.md` with before/after pairs, findings, test commands/results, and limits.

## Task 4 — Review and PR

- [x] Independent whole-branch review; resolve important findings and rerun relevant checks.
- [x] Commit, push a codex branch, create and attach PR with evidence.
- [x] Verify deliverables before marking the goal complete.
