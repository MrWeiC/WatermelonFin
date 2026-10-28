//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import SwiftUI
import UIKit

/// The application initializes behind a silent, once-per-window launch movie.
struct WatermelonLaunchContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.scenePhase)
    private var scenePhase
    @State
    private var isLaunching = true

    @ViewBuilder
    var content: () -> Content

    var body: some View {
        ZStack {
            content()
                .disabled(isLaunching)
                .allowsHitTesting(!isLaunching)
                .accessibilityHidden(isLaunching)

            if isLaunching {
                GeometryReader { geometry in
                    let portrait = UIDevice.current.userInterfaceIdiom == .phone
                        && geometry.size.height > geometry.size.width
                    WatermelonLaunchMovie(portrait: portrait, reduceMotion: reduceMotion, onFinished: finish)
                        .frame(
                            width: geometry.size.width * (portrait ? 0.92 : 0.84),
                            height: geometry.size.height * 0.84
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .background(Color(red: 0.015, green: 0.045, blue: 0.028).ignoresSafeArea())
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("WatermelonFin")
                .accessibilityIdentifier("mobile.launch.animation")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the application never replays an interrupted launch.
            if phase == .background { isLaunching = false }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { finish() }
        }
    }

    private func finish() {
        guard isLaunching else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
            isLaunching = false
        }
    }
}

private struct WatermelonLaunchMovie: View {
    let reduceMotion: Bool
    let onFinished: () -> Void

    @StateObject
    private var playback: LaunchMoviePlayback
    @State
    private var isReady = false

    init(portrait: Bool, reduceMotion: Bool, onFinished: @escaping () -> Void) {
        self.reduceMotion = reduceMotion
        self.onFinished = onFinished
        // Keep the chosen crop and playback position when rotating mid-launch.
        _playback = StateObject(wrappedValue: LaunchMoviePlayback(portrait: portrait))
    }

    var body: some View {
        ZStack {
            if let poster = playback.poster(last: reduceMotion) {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
            }
            if !reduceMotion {
                LaunchMovieLayer(player: playback.player) { isReady = true }
                    .opacity(isReady ? 1 : 0)
            }
        }
        .aspectRatio(playback.aspectRatio, contentMode: .fit)
        .allowsHitTesting(false)
        .task {
            guard reduceMotion || playback.player.currentItem != nil else {
                onFinished()
                return
            }
            if !reduceMotion { playback.player.play() }
            do {
                // A broken asset or stalled decoder must never block app entry.
                try await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 5))
                try Task.checkCancellation()
                onFinished()
            } catch {
                // Removal cancels the timeout, including when backgrounded.
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .AVPlayerItemDidPlayToEndTime, object: playback.player.currentItem
        )) { _ in onFinished() }
        .onReceive(NotificationCenter.default.publisher(
            for: .AVPlayerItemFailedToPlayToEndTime, object: playback.player.currentItem
        )) { _ in onFinished() }
        .onDisappear { playback.stop() }
    }
}

@MainActor
private final class LaunchMoviePlayback: ObservableObject {
    let player: AVPlayer
    let aspectRatio: CGFloat
    private let resource: String

    init(portrait: Bool) {
        resource = "watermelon-launch-\(portrait ? "portrait" : "landscape")"
        aspectRatio = portrait ? 404.0 / 720 : 768.0 / 720
        if let url = Bundle.main.url(forResource: resource, withExtension: "mp4") {
            player = AVPlayer(url: url)
        } else {
            player = AVPlayer()
        }
        player.isMuted = true
        player.volume = 0
        player.actionAtItemEnd = .pause
        // Local files require no streaming buffer or audio-session changes.
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func poster(last: Bool) -> UIImage? {
        guard let url = Bundle.main.url(
            forResource: "\(resource)-\(last ? "last" : "first")", withExtension: "png"
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// A plain video layer avoids playback controls, focus, and full-screen behavior.
private struct LaunchMovieLayer: UIViewRepresentable {
    let player: AVPlayer
    let onReady: () -> Void

    func makeUIView(context: Context) -> LaunchMovieUIView {
        let view = LaunchMovieUIView()
        view.isUserInteractionEnabled = false
        view.videoLayer.videoGravity = .resizeAspect
        view.videoLayer.player = player
        view.observeReadiness(onReady)
        return view
    }

    func updateUIView(_ view: LaunchMovieUIView, context: Context) {}

    static func dismantleUIView(_ view: LaunchMovieUIView, coordinator: ()) {
        view.videoLayer.player = nil
    }
}

private final class LaunchMovieUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var videoLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    private var readiness: NSKeyValueObservation?

    func observeReadiness(_ onReady: @escaping () -> Void) {
        readiness = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in onReady() }
        }
    }
}
