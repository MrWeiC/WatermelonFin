//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI
import UIKit

extension VideoPlayer {
    struct PlaybackControls: View {
        @EnvironmentObject
        private var manager: MediaPlayerManager
        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @State
        private var position = 0.0
        @State
        private var editing = false
        @Default(.VideoPlayer.autoPlayEnabled)
        private var autoPlay
        @Default(.VideoPlayer.Playback.appMaximumBitrate)
        private var bitrate

        private var duration: Double {
            max(1, manager.playbackItem?.baseItem.runtime?.seconds ?? 1)
        }

        var body: some View {
            VStack {
                HStack {
                    Button(L10n.close, systemImage: "xmark") { manager.stop() }
                        .labelStyle(.iconOnly)
                    Spacer()
                    Text(manager.item.displayTitle).lineLimit(1).font(.headline)
                    Spacer()
                    Menu {
                        Toggle(L10n.autoPlay, isOn: $autoPlay)
                        Toggle(L10n.aspectFill, isOn: $containerState.isAspectFilled)
                        Menu(L10n.playbackQuality) {
                            ForEach(PlaybackBitrate.allCases, id: \.self) { value in
                                Button(value.displayTitle) { bitrate = value }
                            }
                        }
                        Menu(L10n.playbackSpeed) {
                            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                                Button("\(rate.formatted())×") { manager.setRate(rate: rate) }
                            }
                        }
                        ForEach(manager.supplements.map(AnyMediaPlayerSupplement.init)) { value in
                            Button(value.displayTitle) { containerState.select(supplement: value) }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel(L10n.info)
                }
                Spacer()
                HStack(spacing: 36) {
                    Button { if let item = manager.queue?.previousItem { manager.playNewItem(provider: item) } } label: {
                        Image(systemName: "backward.end.fill")
                    }.disabled(manager.queue?.previousItem == nil)
                    Button { manager.proxy?.jumpBackward(Defaults[.VideoPlayer.jumpBackwardInterval].rawValue) } label: {
                        Image(systemName: Defaults[.VideoPlayer.jumpBackwardInterval].secondarySystemImage)
                    }
                    Button { manager.togglePlayPause() } label: {
                        Image(systemName: manager.playbackRequestStatus == .playing ? "pause.fill" : "play.fill")
                    }.font(.largeTitle).accessibilityLabel(manager.playbackRequestStatus == .playing ? L10n.pause : L10n.play)
                    Button { manager.proxy?.jumpForward(Defaults[.VideoPlayer.jumpForwardInterval].rawValue) } label: {
                        Image(systemName: Defaults[.VideoPlayer.jumpForwardInterval].systemImage)
                    }
                    Button { if let item = manager.queue?.nextItem { manager.playNewItem(provider: item) } } label: {
                        Image(systemName: "forward.end.fill")
                    }.disabled(manager.queue?.nextItem == nil)
                }.font(.title2)
                Spacer()
                VStack(spacing: 8) {
                    SwiftUI.Slider(value: $position, in: 0 ... duration) { isEditing in
                        editing = isEditing
                        if isEditing {
                            containerState.isScrubbing = true
                        } else {
                            MobilePlaybackSeek.finish(position: position, manager: manager, state: containerState)
                        }
                        containerState.timer.poke()
                    }.accessibilityLabel(L10n.playback)
                    HStack {
                        Text(Duration.seconds(position).formatted(.time(pattern: .hourMinuteSecond)))
                        Spacer()
                        if let item = manager.playbackItem { trackMenus(item) }
                        Text(Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond)))
                    }.font(.caption.monospacedDigit())
                }
            }
            .padding()
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .background(Color.black.opacity(0.35))
            .onReceive(manager.secondsBox.$value) { value in
                if !editing { position = min(duration, max(0, value.seconds)) }
            }
        }

        @ViewBuilder
        private func trackMenus(_ item: MediaPlayerItem) -> some View {
            Menu(L10n.audio, systemImage: "waveform") {
                ForEach(item.audioStreams, id: \.index) { stream in
                    Button(stream.displayTitle ?? stream.language ?? L10n.unknown) { item.selectedAudioStreamIndex = stream.index }
                }
            }.labelStyle(.iconOnly)
            Menu(L10n.subtitles, systemImage: "captions.bubble") {
                Button(L10n.none) { item.selectedSubtitleStreamIndex = -1 }
                ForEach(item.subtitleStreams, id: \.index) { stream in
                    Button(stream.displayTitle ?? stream.language ?? L10n.unknown) { item.selectedSubtitleStreamIndex = stream.index }
                }
            }.labelStyle(.iconOnly)
        }
    }

    struct VideoPlayerContainerView<Player: View, PlaybackControls: View>: UIViewControllerRepresentable {
        let containerState: VideoPlayerContainerState
        let manager: MediaPlayerManager
        let player: () -> Player
        let playbackControls: () -> PlaybackControls

        init(
            containerState: VideoPlayerContainerState,
            manager: MediaPlayerManager,
            @ViewBuilder player: @escaping () -> Player,
            @ViewBuilder playbackControls: @escaping () -> PlaybackControls
        ) {
            self.containerState = containerState
            self.manager = manager
            self.player = player
            self.playbackControls = playbackControls
        }

        func makeUIViewController(context: Context) -> UIVideoPlayerContainerViewController {
            let controller = UIVideoPlayerContainerViewController()
            controller.host = UIHostingController(rootView: AnyView(
                MobilePlayerSurface(player: AnyView(player()), controls: AnyView(playbackControls()))
                    .environmentObject(manager).environmentObject(containerState)
            ))
            controller.containerState = containerState
            controller.manager = manager
            containerState.containerView = controller
            containerState.manager = manager
            containerState.observePlaybackStatus()
            containerState.isPresentingOverlay = true
            return controller
        }

        func updateUIViewController(_ controller: UIVideoPlayerContainerViewController, context: Context) {}
    }

    class UIVideoPlayerContainerViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
        weak var containerState: VideoPlayerContainerState?
        weak var manager: MediaPlayerManager?
        var host: UIHostingController<AnyView>?
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let host else { return }
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            host.didMove(toParent: self)
        }

        func presentSupplementContainer(_ presented: Bool) {
            guard presented else {
                dismiss(animated: true)
                return
            }
            guard let state = containerState, let manager,
                  let supplement = state.selectedSupplement,
                  presentedViewController == nil
            else { return }
            let controller = UIHostingController(rootView: AnyView(
                NavigationStack {
                    AnyMediaPlayerSupplement(supplement).videoPlayerBody.eraseToAnyView()
                        .environmentObject(state)
                        .environmentObject(manager)
                        .navigationTitle(supplement.displayTitle)
                        .toolbar {
                            Button(L10n.close) { [weak self] in
                                self?.containerState?.select(supplement: nil)
                            }
                        }
                }.preferredColorScheme(.dark)
            ))
            controller.presentationController?.delegate = self
            present(controller, animated: true)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            containerState?.selectedSupplement = nil
        }

        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            .allButUpsideDown
        }
    }
}

private struct MobilePlayerSurface: View {
    let player: AnyView
    let controls: AnyView
    @EnvironmentObject
    private var state: VideoPlayerContainerState
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            player.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { state.toggleOverlay() }
            if state.isPresentingOverlay { controls.transition(.opacity) }
        }.animation(.easeInOut(duration: 0.2), value: state.isPresentingOverlay)
    }
}
