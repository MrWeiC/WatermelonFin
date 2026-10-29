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
        @State
        private var trackMenu: TrackMenu?
        @State
        private var isPresentingOptions = false
        @State
        private var pendingSupplement: AnyMediaPlayerSupplement?

        private enum TrackMenu: String, Identifiable {
            case audio
            case subtitles
            var id: String {
                rawValue
            }
        }

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
                    Button {
                        containerState.isPresentingSelection = true
                        isPresentingOptions = true
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel(L10n.info)
                        .sheet(isPresented: $isPresentingOptions, onDismiss: {
                            containerState.isPresentingSelection = false
                            if let supplement = pendingSupplement {
                                pendingSupplement = nil
                                containerState.select(supplement: supplement)
                            }
                        }) {
                            NavigationStack {
                                Form {
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
                                        Button(value.displayTitle) {
                                            pendingSupplement = value
                                            isPresentingOptions = false
                                        }
                                    }
                                }
                                .navigationTitle(L10n.info)
                                .toolbar { Button(L10n.close) { isPresentingOptions = false } }
                            }
                            .presentationDetents([.medium, .large])
                            .preferredColorScheme(.dark)
                        }
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
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                containerState.timer.poke()
            })
            .background(Color.black.opacity(0.35))
            .onReceive(manager.secondsBox.$value) { value in
                if !editing { position = min(duration, max(0, value.seconds)) }
            }
        }

        private func trackMenus(_ item: MediaPlayerItem) -> some View {
            HStack {
                Button { presentTrackMenu(.audio) } label: {
                    Image(systemName: "waveform").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel(L10n.audio)
                Button { presentTrackMenu(.subtitles) } label: {
                    Image(systemName: "captions.bubble").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel(L10n.subtitles)
            }
            .labelStyle(.iconOnly)
            .sheet(item: $trackMenu, onDismiss: { containerState.isPresentingSelection = false }) { menu in
                NavigationStack {
                    List {
                        if menu == .subtitles {
                            Button(L10n.none) {
                                item.selectedSubtitleStreamIndex = -1
                                trackMenu = nil
                            }
                        }
                        ForEach(menu == .audio ? item.audioStreams : item.subtitleStreams, id: \.index) { stream in
                            Button(stream.displayTitle ?? stream.language ?? L10n.unknown) {
                                if menu == .audio { item.selectedAudioStreamIndex = stream.index }
                                else { item.selectedSubtitleStreamIndex = stream.index }
                                trackMenu = nil
                            }
                        }
                    }
                    .navigationTitle(menu == .audio ? L10n.audio : L10n.subtitles)
                    .toolbar { Button(L10n.close) { trackMenu = nil } }
                }
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            }
        }

        private func presentTrackMenu(_ menu: TrackMenu) {
            containerState.isPresentingSelection = true
            trackMenu = menu
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
