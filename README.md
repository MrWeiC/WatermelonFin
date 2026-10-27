<div align="center">

# WatermelonFin

**A native Jellyfin client for Apple TV and iPhone**

<img src="https://img.shields.io/badge/tvOS-17+-blue"/>
<img src="https://img.shields.io/badge/Jellyfin-10.11-9962be"/>
<img src="https://img.shields.io/badge/License-MPL%202.0-brightgreen"/>

</div>

> **Note:** WatermelonFin is an independent project. It is **not affiliated with or endorsed by** [Jellyfin](https://jellyfin.org), [Swiftfin](https://github.com/jellyfin/Swiftfin), or [Reefy](https://github.com/jmhunter83/reefy). It is developed separately with a focus on Apple TV.

---

## About

**WatermelonFin** is a native Jellyfin media client for Apple TV and iPhone. It uses MPV for direct playback and is designed to feel native on tvOS.

Apple TV uses remote-focused browsing; iPhone has a native touch interface. Both platforms share the same Jellyfin session, library, playlist, and playback models. See [iPhone setup and validation](Documentation/iphone.md).

---

## Features

- **tvOS 18 Liquid Glass** — Native glass transport bar with tvOS 17 fallback
- **Redesigned playback controls** — Clean layout in the bottom of the screen
- **Native progress slider** — Pill-shaped playback scrubber
- **Full-screen item views** — Proper detail views, not cards
- **Native Jellyfin video playlists** — Browse playlists, create private lists, add videos, and remove playlist entries directly on the server
- **Improved focus states** — Smooth scale animations on button focus
- **MPV-based playback** — Wide codec and subtitle support for your media files

Playlist membership is stored by Jellyfin. Watched status remains the signed-in user's normal Jellyfin item state, so the same movie has one consistent watched status across the library and every playlist.

---

## Build from Source

WatermelonFin source is available under the MPL 2.0 license. The planned US App Store price is $0.99 as a one-time purchase; no paid iPhone release is available yet. TestFlight validation comes before the store launch. You can also build from source:

**Requirements:**
- Xcode (latest)
- Apple TV (tvOS 17.5+) or iPhone (iOS 17.5+)
- A Jellyfin media server (10.11+ recommended)

See the [Documentation](Documentation/) directory for build details.

Before opening a pull request, run the local validation commands in [Contributing](Documentation/contributing.md#before-opening-a-pull-request) so GitHub Actions are used for confirmation rather than first-pass lint or build failures.

---

## Acknowledgments

WatermelonFin stands on the work of others:

- [Jellyfin](https://jellyfin.org) — The free software media system
- [Swiftfin](https://github.com/jellyfin/Swiftfin) — The original native Swift Jellyfin client
- [Reefy](https://github.com/jmhunter83/reefy) — A tvOS-focused fork in this project's lineage

The source lineage is: **WatermelonFin <- Reefy <- Swiftfin**.

---

## License

This project is licensed under the [Mozilla Public License 2.0](LICENSE.md). Original copyright and license notices are retained where required by upstream source files.
