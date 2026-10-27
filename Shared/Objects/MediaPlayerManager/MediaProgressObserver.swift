//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import Foundation
import JellyfinAPI
import UIKit

class MediaProgressObserver: ViewModel, MediaPlayerObserver {

    weak var manager: MediaPlayerManager? {
        didSet {
            if let manager {
                setup(with: manager)
            }
        }
    }

    private let timer = PokeIntervalTimer()
    private var hasSentStart = false
    private var hasStopped = false
    private var reportQueue: PlaybackReportQueue?
    private var reportingClient: JellyfinClient?
    private weak var item: MediaPlayerItem?
    private var lastPlaybackRequestStatus: MediaPlayerManager.PlaybackRequestStatus = .playing

    init(item: MediaPlayerItem) {
        self.item = item
        super.init()
    }

    private func sendReport() {
        guard !hasStopped, let item else { return }

        if !hasSentStart {
            sendStartReport(for: item, seconds: manager?.seconds)
            return
        }

        switch lastPlaybackRequestStatus {
        case .playing:
            if hasSentStart {
                sendProgressReport(for: item, seconds: manager?.seconds)
            } else {
                sendStartReport(for: item, seconds: manager?.seconds)
            }
        case .paused:
            sendProgressReport(for: item, seconds: manager?.seconds, isPaused: true)
        }
    }

    private func setup(with manager: MediaPlayerManager) {
        cancellables = []
        reportingClient = userSession?.client
        reportQueue = manager.reportQueue

        timer.sink { [weak self] in
            self?.sendReport()
            self?.timer.poke()
        }
        .store(in: &cancellables)

        manager.actions
            .sink { [weak self] in self?.didReceive(action: $0) }
            .store(in: &cancellables)

        manager.$playbackItem
            .sink { [weak self] in self?.playbackItemDidChange($0) }
            .store(in: &cancellables)

        manager.$playbackRequestStatus
            .sink { [weak self] in self?.playbackRequestStatusDidChange($0) }
            .store(in: &cancellables)

        // Flush current position to the server when the app is about to resign active
        // (device sleep, Home press). This fires before didEnterBackground, giving the
        // network request time to land before the system suspends us.
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                guard let self, let item = self.item else { return }
                self.sendProgressReport(
                    for: item,
                    seconds: self.manager?.seconds,
                    isPaused: self.lastPlaybackRequestStatus == .paused
                )
            }
            .store(in: &cancellables)
    }

    private func playbackItemDidChange(_ newItem: MediaPlayerItem?) {
        guard !hasStopped, let item, newItem !== item else { return }
        // Each item owns its own observer. Retiring this one prevents it from
        // following the next item and duplicating that item's reports.
        finishReporting(for: item)
    }

    private func finishReporting(for item: MediaPlayerItem) {
        guard !hasStopped else { return }
        hasStopped = true
        cancellables = []
        timer.stop()
        sendStopReport(for: item, seconds: manager?.seconds)
        self.item = nil
    }

    private func playbackRequestStatusDidChange(_ newStatus: MediaPlayerManager.PlaybackRequestStatus) {
        timer.poke()
        lastPlaybackRequestStatus = newStatus
        sendReport()
    }

    private func didReceive(action: MediaPlayerManager._Action) {
        switch action {
        case .stop, .error:
            if let item { finishReporting(for: item) }
        default:
            break
        }
    }

    private func sendStartReport(for item: MediaPlayerItem, seconds: Duration?) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        guard !hasSentStart, let client = reportingClient, let reportQueue else { return }
        hasSentStart = true
        reportQueue.enqueue {
            do {
                var info = PlaybackStartInfo()
                info.audioStreamIndex = item.selectedAudioStreamIndex
                info.itemID = item.baseItem.id
                info.mediaSourceID = item.mediaSource.id
                info.playSessionID = item.playSessionID
                info.positionTicks = seconds?.ticks
                info.subtitleStreamIndex = item.selectedSubtitleStreamIndex

                let request = Paths.reportPlaybackStart(info)
                _ = try await client.send(request)

            } catch {
                if !self.hasStopped { self.hasSentStart = false }
                self.logger.error("Failed to send playback start report: \(error.localizedDescription)")
            }
        }
    }

    private func sendStopReport(for item: MediaPlayerItem, seconds: Duration?) {

        // Debug logging: Track what position is being reported to help diagnose
        // why episodes may not be marked as played (server expects ~90% threshold)
        if let seconds, let runtime = item.baseItem.runtime, runtime > .zero {
            let percentage = (seconds.seconds / runtime.seconds) * 100
            logger
                .info(
                    "📊 Stop report: '\(item.baseItem.displayTitle)' at \(Int(percentage))% (\(Int(seconds.seconds))s / \(Int(runtime.seconds))s)"
                )
        } else {
            logger.warning("📊 Stop report: '\(item.baseItem.displayTitle)' - missing position or runtime data")
        }

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        guard let client = reportingClient, let reportQueue else { return }
        reportQueue.enqueue {
            do {
                let info = Self.playbackStopInfo(for: item, seconds: seconds)

                let request = Paths.reportPlaybackStopped(info)
                _ = try await client.send(request)
            } catch {
                self.logger.error("Failed to send playback stop report: \(error.localizedDescription)")
            }
        }
    }

    static func playbackStopInfo(for item: MediaPlayerItem, seconds: Duration?) -> PlaybackStopInfo {
        var info = PlaybackStopInfo()
        info.itemID = item.baseItem.id
        info.mediaSourceID = item.mediaSource.id
        info.playSessionID = item.playSessionID
        info.positionTicks = seconds?.ticks
        return info
    }

    private func sendProgressReport(for item: MediaPlayerItem, seconds: Duration?, isPaused: Bool = false) {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        guard let client = reportingClient, let reportQueue else { return }
        reportQueue.enqueue {
            do {
                var info = PlaybackProgressInfo()
                info.audioStreamIndex = item.selectedAudioStreamIndex
                info.isPaused = isPaused
                info.itemID = item.baseItem.id
                info.mediaSourceID = item.mediaSource.id
                info.playSessionID = item.playSessionID
                info.positionTicks = seconds?.ticks
                info.subtitleStreamIndex = item.selectedSubtitleStreamIndex

                let request = Paths.reportPlaybackProgress(info)
                _ = try await client.send(request)
            } catch {
                // Don't log progress errors at error level - they're frequent and expected during network issues
                self.logger.warning("Failed to send playback progress report: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        timer.stop()
        cancellables.removeAll()
    }
}
