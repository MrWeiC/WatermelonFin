//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Defaults
import Factory
import Foundation
import JellyfinAPI
import Logging
import MPVKit
import SwiftUI
import UIKit

@MainActor
class MPVMediaPlayerProxy: VideoMediaPlayerProxy,
    MediaPlayerOffsetConfigurable,
    MediaPlayerSubtitleConfigurable
{

    let isBuffering: PublishedBox<Bool> = .init(initialValue: false)
    let videoSize: PublishedBox<CGSize> = .init(initialValue: .zero)

    private weak var containerState: VideoPlayerContainerState?
    private weak var playerView: MPVPlayerSurfaceView?
    private var pendingPlaybackItem: MediaPlayerItem?

    weak var manager: MediaPlayerManager? {
        didSet {
            for var o in observers {
                o.manager = manager
            }
        }
    }

    var observers: [any MediaPlayerObserver] = [
        NowPlayableObserver(),
    ]

    func play() {
        playerView?.play()
    }

    func pause() {
        playerView?.pause()
    }

    func stop() {
        playerView?.stop()
    }

    func jumpForward(_ seconds: Duration) {
        playerView?.seek(by: seconds.seconds)
    }

    func jumpBackward(_ seconds: Duration) {
        playerView?.seek(by: -seconds.seconds)
    }

    func setRate(_ rate: Float) {
        playerView?.setRate(Double(rate))
    }

    func setSeconds(_ seconds: Duration) {
        playerView?.seek(to: seconds.seconds)
    }

    func setAspectFill(_ aspectFill: Bool) {
        playerView?.setAspectFill(aspectFill)
    }

    func setAudioStream(_ stream: MediaStream) {
        guard let playbackItem = manager?.playbackItem,
              let trackID = Self.audioTrackID(for: stream.index, audioStreams: playbackItem.audioStreams)
        else {
            return
        }

        playerView?.setAudioTrack(trackID)
    }

    func setSubtitleStream(_ stream: MediaStream) {
        guard let playbackItem = manager?.playbackItem,
              let trackID = Self.subtitleTrackID(for: stream.index, subtitleStreams: playbackItem.subtitleStreams)
        else {
            return
        }

        if trackID < 0 {
            playerView?.disableSubtitles()
        } else {
            playerView?.setSubtitleTrack(trackID)
        }
    }

    func setAudioOffset(_ seconds: Duration) {
        playerView?.setAudioOffset(seconds.seconds)
    }

    func setSubtitleOffset(_ seconds: Duration) {
        playerView?.setSubtitleOffset(seconds.seconds)
    }

    func setSubtitleColor(_ color: Color) {
        playerView?.setSubtitleColor(color.uiColor.mpvHexColor)
    }

    func setSubtitleFontName(_ fontName: String) {
        playerView?.setSubtitleFontName(fontName)
    }

    func setSubtitleFontSize(_ fontSize: Int) {
        playerView?.setSubtitleFontSize(fontSize)
    }

    var videoPlayerBody: some View {
        MPVPlayerView(proxy: self)
    }

    static func audioTrackID(for streamIndex: Int?, audioStreams: [MediaStream]) -> Int? {
        guard let streamIndex, streamIndex >= 0 else { return nil }
        guard let index = audioStreams.firstIndex(where: { $0.index == streamIndex }) else { return nil }
        return index + 1
    }

    static func subtitleTrackID(for streamIndex: Int?, subtitleStreams: [MediaStream]) -> Int? {
        guard let streamIndex else { return -1 }
        guard streamIndex >= 0 else { return -1 }
        guard let index = subtitleStreams.firstIndex(where: { $0.index == streamIndex }) else { return nil }
        return index + 1
    }

    static func volumePercent(for item: BaseItemDto) -> Double {
        guard item.type == .audio,
              Defaults[.VideoPlayer.Audio.replayGainEnabled],
              let normalizationGain = item.normalizationGain
        else {
            return 100
        }

        let finalGain = ReplayGainCalculator.calculateFinalGain(
            normalizationGain: normalizationGain,
            preAmp: Defaults[.VideoPlayer.Audio.replayGainPreAmp],
            preventClipping: Defaults[.VideoPlayer.Audio.replayGainPreventClipping]
        )

        return Double(ReplayGainCalculator.dBToLinear(finalGain) * 100)
    }

    fileprivate func attach(_ playerView: MPVPlayerSurfaceView, containerState: VideoPlayerContainerState) {
        self.playerView = playerView
        self.containerState = containerState

        if let pendingPlaybackItem {
            playNew(item: pendingPlaybackItem)
        }
    }

    fileprivate func detach(_ playerView: MPVPlayerSurfaceView) {
        if self.playerView === playerView {
            self.playerView = nil
        }
    }

    fileprivate func playNew(item: MediaPlayerItem) {
        pendingPlaybackItem = item
        guard let playerView else { return }

        let startSeconds = max(.zero, (item.baseItem.startSeconds ?? .zero) - Duration.seconds(Defaults[.VideoPlayer.resumeOffset]))
        let subtitleID = Self.subtitleTrackID(
            for: item.selectedSubtitleStreamIndex,
            subtitleStreams: item.subtitleStreams
        )
        let audioID = Self.audioTrackID(
            for: item.selectedAudioStreamIndex,
            audioStreams: item.audioStreams
        )

        playerView.load(
            url: item.url,
            headers: Self.authorizationHeaders(),
            startPosition: startSeconds.seconds,
            volumePercent: Self.volumePercent(for: item.baseItem),
            audioOutputMode: Defaults[.VideoPlayer.Audio.outputMode],
            externalSubtitles: Self.externalSubtitleURLs(for: item.subtitleStreams).map(\.absoluteString),
            initialSubtitleID: subtitleID,
            initialAudioID: audioID
        )
    }

    fileprivate func didUpdatePosition(_ seconds: Double, duration: Double) {
        let position = Duration.seconds(seconds)

        if containerState?.isScrubbing != true {
            containerState?.scrubbedSeconds.value = position
        }

        manager?.seconds = position
    }

    fileprivate func didChangePause(_ isPaused: Bool) {
        Task {
            await manager?.setPlaybackRequestStatus(status: isPaused ? .paused : .playing)
        }
    }

    fileprivate func didChangeLoading(_ isLoading: Bool) {
        isBuffering.value = isLoading
    }

    fileprivate func didChangeVideoSize(_ size: CGSize) {
        videoSize.value = size
    }

    fileprivate func didEndPlayback() {
        Task {
            await manager?.ended()
        }
    }

    fileprivate func didFailPlayback(_ message: String) {
        Task {
            await manager?.error(ErrorMessage(message))
        }
    }

    private static func authorizationHeaders() -> [String: String]? {
        guard let accessToken = Container.shared.currentUserSession()?.client.configuration.accessToken else { return nil }

        return [
            "Authorization": "MediaBrowser Token=\"\(accessToken.escapedMPVHeaderValue)\"",
        ]
    }

    private static func externalSubtitleURLs(for subtitleStreams: [MediaStream]) -> [URL] {
        subtitleStreams
            .filter { $0.deliveryMethod == .external }
            .compactMap(externalSubtitleURL)
    }

    private static func externalSubtitleURL(for stream: MediaStream) -> URL? {
        guard let deliveryURL = stream.deliveryURL,
              let client = Container.shared.currentUserSession()?.client
        else {
            return nil
        }

        let deliveryPath = deliveryURL.removingFirst(if: client.configuration.url.absoluteString.last == "/")
        return client.fullURL(with: deliveryPath)
    }
}

private extension MPVMediaPlayerProxy {

    struct MPVPlayerView: View {

        let proxy: MPVMediaPlayerProxy

        @EnvironmentObject
        private var containerState: VideoPlayerContainerState
        @EnvironmentObject
        private var manager: MediaPlayerManager

        var body: some View {
            MPVPlayerRepresentable(proxy: proxy, containerState: containerState)
                .onAppear {
                    if let item = manager.playbackItem {
                        proxy.playNew(item: item)
                    }
                }
                .onReceive(manager.$playbackItem) { playbackItem in
                    guard let playbackItem else { return }
                    proxy.playNew(item: playbackItem)
                }
                .onReceive(manager.$state) { state in
                    if state == .stopped {
                        proxy.stop()
                    }
                }
                .backport
                .onChange(of: manager.rate) { _, newValue in
                    proxy.setRate(newValue)
                }
        }
    }

    struct MPVPlayerRepresentable: UIViewRepresentable {

        let proxy: MPVMediaPlayerProxy
        let containerState: VideoPlayerContainerState

        func makeUIView(context: Context) -> MPVPlayerSurfaceView {
            let view = MPVPlayerSurfaceView(proxy: proxy)
            proxy.attach(view, containerState: containerState)
            return view
        }

        func updateUIView(_ uiView: MPVPlayerSurfaceView, context: Context) {
            proxy.attach(uiView, containerState: containerState)
        }

        static func dismantleUIView(_ uiView: MPVPlayerSurfaceView, coordinator: ()) {
            uiView.proxy?.detach(uiView)
            uiView.stop()
        }
    }
}

private final class MPVPlayerSurfaceView: UIView, MPVLayerRendererDelegate {

    fileprivate weak var proxy: MPVMediaPlayerProxy?

    private let displayLayer = AVSampleBufferDisplayLayer()
    private let renderer: MPVLayerRenderer

    init(proxy: MPVMediaPlayerProxy) {
        self.proxy = proxy
        self.renderer = MPVLayerRenderer(displayLayer: displayLayer)

        super.init(frame: .zero)

        backgroundColor = .black
        clipsToBounds = true
        displayLayer.videoGravity = .resizeAspect
        displayLayer.isHidden = false
        displayLayer.opacity = 1
        displayLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(displayLayer)
        renderer.delegate = self

        do {
            try renderer.start()
        } catch {
            proxy.didFailPlayback("MPV player failed to start: \(error.localizedDescription)")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        displayLayer.isHidden = false
        displayLayer.opacity = 1
        CATransaction.commit()
    }

    func load(
        url: URL,
        headers: [String: String]?,
        startPosition: Double,
        volumePercent: Double,
        audioOutputMode: AudioOutputMode,
        externalSubtitles: [String],
        initialSubtitleID: Int?,
        initialAudioID: Int?
    ) {
        renderer.load(
            url: url,
            headers: headers,
            startPosition: startPosition,
            volumePercent: volumePercent,
            audioOutputMode: audioOutputMode,
            externalSubtitles: externalSubtitles,
            initialSubtitleID: initialSubtitleID,
            initialAudioID: initialAudioID
        )
    }

    func play() {
        renderer.play()
    }

    func pause() {
        renderer.pause()
    }

    func stop() {
        renderer.stop()
    }

    func seek(to seconds: Double) {
        renderer.seek(to: seconds)
    }

    func seek(by seconds: Double) {
        renderer.seek(by: seconds)
    }

    func setRate(_ rate: Double) {
        renderer.setRate(rate)
    }

    func setAudioTrack(_ trackID: Int) {
        renderer.setAudioTrack(trackID)
    }

    func setSubtitleTrack(_ trackID: Int) {
        renderer.setSubtitleTrack(trackID)
    }

    func disableSubtitles() {
        renderer.disableSubtitles()
    }

    func setAspectFill(_ aspectFill: Bool) {
        displayLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
    }

    func setAudioOffset(_ seconds: Double) {
        renderer.setProperty(name: "audio-delay", value: String(seconds))
    }

    func setSubtitleOffset(_ seconds: Double) {
        renderer.setProperty(name: "sub-delay", value: String(seconds))
    }

    func setSubtitleColor(_ color: String) {
        renderer.setProperty(name: "sub-color", value: color)
    }

    func setSubtitleFontName(_ fontName: String) {
        renderer.setSubtitleFontName(fontName)
    }

    func setSubtitleFontSize(_ fontSize: Int) {
        renderer.setProperty(name: "sub-font-size", value: String(fontSize))
    }

    func renderer(_ renderer: MPVLayerRenderer, didUpdatePosition position: Double, duration: Double) {
        proxy?.didUpdatePosition(position, duration: duration)
    }

    func renderer(_ renderer: MPVLayerRenderer, didChangePause isPaused: Bool) {
        proxy?.didChangePause(isPaused)
    }

    func renderer(_ renderer: MPVLayerRenderer, didChangeLoading isLoading: Bool) {
        proxy?.didChangeLoading(isLoading)
    }

    func renderer(_ renderer: MPVLayerRenderer, didChangeVideoSize size: CGSize) {
        proxy?.didChangeVideoSize(size)
    }

    func rendererDidEndPlayback(_ renderer: MPVLayerRenderer) {
        proxy?.didEndPlayback()
    }

    func renderer(_ renderer: MPVLayerRenderer, didFail message: String) {
        proxy?.didFailPlayback(message)
    }
}

private protocol MPVLayerRendererDelegate: AnyObject {
    func renderer(_ renderer: MPVLayerRenderer, didUpdatePosition position: Double, duration: Double)
    func renderer(_ renderer: MPVLayerRenderer, didChangePause isPaused: Bool)
    func renderer(_ renderer: MPVLayerRenderer, didChangeLoading isLoading: Bool)
    func renderer(_ renderer: MPVLayerRenderer, didChangeVideoSize size: CGSize)
    func rendererDidEndPlayback(_ renderer: MPVLayerRenderer)
    func renderer(_ renderer: MPVLayerRenderer, didFail message: String)
}

private final class MPVLayerRenderer {

    enum RendererError: Error {
        case mpvCreationFailed
        case mpvInitialization(Int32)
    }

    private static let bundledSubtitleFontFamily = "Noto Sans CJK TC"
    private static let bundledSubtitleFontResource = "NotoSansCJKtc-Regular"
    private static let queueKey = DispatchSpecificKey<Bool>()

    private let displayLayer: AVSampleBufferDisplayLayer
    private let logger = Logger.watermelonfin()
    private let queue = DispatchQueue(label: "watermelonfin.mpv.renderer", qos: .userInitiated)
    private var mpv: OpaquePointer?
    private var statusObservation: NSKeyValueObservation?
    private var isStopping = false
    private var isLoading = false
    private var isSeeking = false
    private var isReadyToSeek = false
    private var lastProgressUpdateTime: CFAbsoluteTime = 0

    private var currentPosition = 0.0
    private var currentDuration = 0.0
    private var pendingExternalSubtitles: [String] = []
    private var initialSubtitleID: Int?
    private var initialAudioID: Int?

    weak var delegate: MPVLayerRendererDelegate?

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        queue.setSpecific(key: Self.queueKey, value: true)
        statusObservation = displayLayer.observe(\.status, options: [.new]) { [weak self] layer, _ in
            guard let self, layer.status == .failed else { return }

            self.logger.warning(
                "MPV display layer failed",
                metadata: [
                    "requiresFlushToResumeDecoding": "\(layer.requiresFlushToResumeDecoding)",
                ]
            )

            self.queue.async { [weak self] in
                guard let self, let handle = self.mpv else { return }
                self.commandSync(handle, ["set", "hwdec", "no"])
            }
        }
    }

    deinit {
        stop()
    }

    func start() throws {
        guard mpv == nil else { return }
        guard let handle = mpv_create() else {
            throw RendererError.mpvCreationFailed
        }

        mpv = handle

        #if DEBUG
        checkError(mpv_request_log_messages(handle, "warn"))
        #else
        checkError(mpv_request_log_messages(handle, "no"))
        #endif

        let layerPointer = Int(bitPattern: Unmanaged.passUnretained(displayLayer).toOpaque())
        var displayLayerPointer = Int64(layerPointer)
        checkError(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &displayLayerPointer))
        checkError(mpv_set_option_string(handle, "vo", "avfoundation"))

        #if os(tvOS) || targetEnvironment(simulator)
        checkError(mpv_set_option_string(handle, "avfoundation-composite-osd", "no"))
        #else
        checkError(mpv_set_option_string(handle, "avfoundation-composite-osd", "yes"))
        #endif

        #if targetEnvironment(simulator)
        checkError(mpv_set_option_string(handle, "hwdec", "no"))
        #else
        checkError(mpv_set_option_string(handle, "hwdec", "videotoolbox"))
        #endif

        checkError(mpv_set_option_string(handle, "hwdec-codecs", "all"))
        checkError(mpv_set_option_string(handle, "hwdec-software-fallback", "yes"))
        checkError(mpv_set_option_string(handle, "sub-scale-with-window", "no"))
        checkError(mpv_set_option_string(handle, "sub-use-margins", "no"))
        checkError(mpv_set_option_string(handle, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(handle, "subs-fallback", "yes"))
        applyBundledSubtitleFont(on: handle)

        #if os(tvOS)
        checkError(mpv_set_option_string(handle, "target-colorspace-hint", "yes"))
        #endif

        let status = mpv_initialize(handle)
        guard status >= 0 else {
            throw RendererError.mpvInitialization(status)
        }

        observeProperties()

        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let renderer = Unmanaged<MPVLayerRenderer>.fromOpaque(context).takeUnretainedValue()
            renderer.processEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true

        guard let handle = mpv else {
            isStopping = false
            return
        }

        mpv_set_wakeup_callback(handle, nil, nil)

        let quit = { [self] in
            _ = commandSync(handle, ["quit"])
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) == true {
            quit()
        } else {
            queue.sync(execute: quit)
        }

        mpv = nil
        DispatchQueue.global(qos: .userInitiated).async {
            mpv_terminate_destroy(handle)
        }

        DispatchQueue.main.async { [displayLayer] in
            if #available(iOS 18.0, tvOS 17.0, *) {
                displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true)
            } else {
                displayLayer.flushAndRemoveImage()
            }
        }

        isStopping = false
    }

    func load(
        url: URL,
        headers: [String: String]?,
        startPosition: Double,
        volumePercent: Double,
        audioOutputMode: AudioOutputMode,
        externalSubtitles: [String],
        initialSubtitleID: Int?,
        initialAudioID: Int?
    ) {
        pendingExternalSubtitles = externalSubtitles
        self.initialSubtitleID = initialSubtitleID
        self.initialAudioID = initialAudioID

        queue.async { [weak self] in
            guard let self, let handle = self.mpv else { return }

            self.isLoading = true
            self.isReadyToSeek = false
            self.notifyLoading(true)

            self.commandSync(handle, ["stop"])
            self.updateHTTPHeaders(headers)
            self.setPropertyOnQueue(name: "start", value: String(format: "%.2f", max(0, startPosition)))
            self.applyVolume(volumePercent)
            self.applyAudioOutputMode(audioOutputMode)

            if let audioID = initialAudioID, audioID > 0 {
                self.setAudioTrackOnQueue(audioID)
            }

            if externalSubtitles.isEmpty {
                if let subtitleID = initialSubtitleID {
                    self.setSubtitleTrackOnQueue(subtitleID)
                } else {
                    self.disableSubtitlesOnQueue()
                }
            } else {
                self.disableSubtitlesOnQueue()
            }

            let target = url.isFileURL ? url.path : url.absoluteString
            self.command(handle, ["loadfile", target, "replace"])
        }
    }

    func play() {
        setProperty(name: "pause", value: "no")
    }

    func pause() {
        setProperty(name: "pause", value: "yes")
    }

    func seek(to seconds: Double) {
        guard let handle = mpv else { return }
        currentPosition = max(0, seconds)
        commandSync(handle, ["seek", String(currentPosition), "absolute"])
    }

    func seek(by seconds: Double) {
        guard let handle = mpv else { return }
        currentPosition = max(0, currentPosition + seconds)
        commandSync(handle, ["seek", String(seconds), "relative"])
    }

    func setRate(_ rate: Double) {
        setProperty(name: "speed", value: String(rate))
    }

    func setAudioTrack(_ trackID: Int) {
        setProperty(name: "aid", value: String(trackID))
    }

    func setSubtitleTrack(_ trackID: Int) {
        if trackID < 0 {
            disableSubtitles()
        } else {
            setProperty(name: "sid", value: String(trackID))
        }
    }

    func disableSubtitles() {
        setProperty(name: "sid", value: "no")
    }

    func setProperty(name: String, value: String) {
        queue.async { [weak self] in
            guard let self, self.mpv != nil else { return }
            self.setPropertyOnQueue(name: name, value: value)
        }
    }

    func setSubtitleFontName(_ fontName: String) {
        let resolvedFontName = fontName.hasPrefix(".") ? Self.bundledSubtitleFontFamily : fontName
        setProperty(name: "sub-font", value: resolvedFontName)
    }

    private func applyBundledSubtitleFont(on handle: OpaquePointer) {
        guard let fontURL = Self.bundledSubtitleFontURL else {
            logger.warning("Bundled MPV subtitle font is missing")
            return
        }

        setOptionalStartupOption(handle, name: "sub-font-provider", value: "auto")
        setOptionalStartupOption(handle, name: "sub-fonts-dir", value: fontURL.deletingLastPathComponent().path)
        setOptionalStartupOption(handle, name: "sub-font", value: Self.bundledSubtitleFontFamily)

        logger.info(
            "MPV bundled subtitle font enabled",
            metadata: [
                "font": "\(Self.bundledSubtitleFontFamily)",
                "fontsDir": "\(fontURL.deletingLastPathComponent().path)",
            ]
        )
    }

    private func setOptionalStartupOption(_ handle: OpaquePointer, name: String, value: String) {
        let status = mpv_set_option_string(handle, name, value)
        if status < 0 {
            logger.warning("MPV failed to set optional option \(name): \(String(cString: mpv_error_string(status)))")
        }
    }

    private static var bundledSubtitleFontURL: URL? {
        Bundle.main.url(
            forResource: bundledSubtitleFontResource,
            withExtension: "otf"
        ) ?? Bundle.main.url(
            forResource: bundledSubtitleFontResource,
            withExtension: "otf",
            subdirectory: "Fonts"
        ) ?? Bundle.main.url(
            forResource: bundledSubtitleFontResource,
            withExtension: "otf",
            subdirectory: "Resources/Fonts"
        )
    }

    private func setPropertyOnQueue(name: String, value: String) {
        guard let handle = mpv else { return }
        let status = mpv_set_property_string(handle, name, value)
        if status < 0 {
            logger.warning("MPV failed to set \(name): \(String(cString: mpv_error_string(status)))")
        }
    }

    private func setAudioTrackOnQueue(_ trackID: Int) {
        setPropertyOnQueue(name: "aid", value: String(trackID))
    }

    private func setSubtitleTrackOnQueue(_ trackID: Int) {
        if trackID < 0 {
            disableSubtitlesOnQueue()
        } else {
            setPropertyOnQueue(name: "sid", value: String(trackID))
        }
    }

    private func disableSubtitlesOnQueue() {
        setPropertyOnQueue(name: "sid", value: "no")
    }

    private func clearPropertyOnQueue(name: String) {
        guard let handle = mpv else { return }
        let status = mpv_set_property(handle, name, MPV_FORMAT_NONE, nil)
        if status < 0 {
            logger.warning("MPV failed to clear \(name): \(String(cString: mpv_error_string(status)))")
        }
    }

    private func updateHTTPHeaders(_ headers: [String: String]?) {
        guard let headers, !headers.isEmpty else {
            clearPropertyOnQueue(name: "http-header-fields")
            return
        }

        let headerString = headers
            .map { key, value in "\(key): \(value)" }
            .joined(separator: "\r\n")
        setPropertyOnQueue(name: "http-header-fields", value: headerString)
    }

    private func applyVolume(_ volumePercent: Double) {
        let clampedVolume = max(0, min(volumePercent, 1000))
        setPropertyOnQueue(name: "volume-max", value: String(max(130, clampedVolume)))
        setPropertyOnQueue(name: "volume", value: String(format: "%.4f", clampedVolume))
    }

    private func applyAudioOutputMode(_ mode: AudioOutputMode) {
        switch mode {
        case .auto:
            setPropertyOnQueue(name: "audio-spdif", value: "no")
            setPropertyOnQueue(name: "audio-channels", value: "auto")
        case .stereo:
            setPropertyOnQueue(name: "audio-spdif", value: "no")
            setPropertyOnQueue(name: "audio-channels", value: "stereo")
        case .passthrough:
            setPropertyOnQueue(name: "audio-channels", value: "auto")
            setPropertyOnQueue(name: "audio-spdif", value: "ac3,dts,dts-hd,eac3,truehd")
        }
    }

    private func observeProperties() {
        guard let handle = mpv else { return }

        let properties: [(String, mpv_format)] = [
            ("duration", MPV_FORMAT_DOUBLE),
            ("time-pos", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG),
            ("paused-for-cache", MPV_FORMAT_FLAG),
            ("track-list/count", MPV_FORMAT_INT64),
            ("video-params/w", MPV_FORMAT_INT64),
            ("video-params/h", MPV_FORMAT_INT64),
        ]

        for (name, format) in properties {
            mpv_observe_property(handle, 0, name, format)
        }
    }

    private func processEvents() {
        queue.async { [weak self] in
            guard let self else { return }

            while self.mpv != nil, !self.isStopping {
                guard let handle = self.mpv,
                      let pointer = mpv_wait_event(handle, 0)
                else {
                    return
                }

                let event = pointer.pointee
                if event.event_id == MPV_EVENT_NONE { break }
                self.handleEvent(event)
                if event.event_id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }

    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_START_FILE:
            logger.info("MPV start file")

        case MPV_EVENT_FILE_LOADED:
            logger.info("MPV file loaded")

            if !pendingExternalSubtitles.isEmpty, let handle = mpv {
                for subtitle in pendingExternalSubtitles {
                    commandSync(handle, ["sub-add", subtitle, "auto"])
                }
                pendingExternalSubtitles = []
            }

            if let audioID = initialAudioID, audioID > 0 {
                setAudioTrackOnQueue(audioID)
            }

            if let subtitleID = initialSubtitleID {
                setSubtitleTrackOnQueue(subtitleID)
            } else {
                disableSubtitlesOnQueue()
            }

            isReadyToSeek = true
            isLoading = false
            notifyLoading(false)

        case MPV_EVENT_SEEK:
            isSeeking = true
            isLoading = true
            notifyLoading(true)

        case MPV_EVENT_PLAYBACK_RESTART:
            logger.info("MPV playback restarted")
            isSeeking = false
            isLoading = false
            notifyLoading(false)

        case MPV_EVENT_PROPERTY_CHANGE:
            if let namePointer = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee.name {
                refreshProperty(named: String(cString: namePointer))
            }

        case MPV_EVENT_END_FILE:
            guard let endFile = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else {
                return
            }

            logger.info(
                "MPV end file",
                metadata: [
                    "reason": "\(endFile.reason.rawValue)",
                    "error": "\(endFile.error)",
                    "errorMessage": "\(String(cString: mpv_error_string(Int32(endFile.error))))",
                ]
            )

            switch PlaybackEndAction.resolve(
                isError: endFile.reason == MPV_END_FILE_REASON_ERROR,
                isEOF: endFile.reason == MPV_END_FILE_REASON_EOF,
                isStopping: isStopping,
                isReady: isReadyToSeek
            ) {
            case .ignore:
                return
            case .fail:
                isLoading = false
                isReadyToSeek = false
                notifyLoading(false)
                notifyFailure(String(cString: mpv_error_string(Int32(endFile.error))))
            case .finish:
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.rendererDidEndPlayback(self)
                }
            }

        case MPV_EVENT_LOG_MESSAGE:
            if let logMessage = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee {
                let component = String(cString: logMessage.prefix)
                let text = String(cString: logMessage.text)
                let lowercasedText = text.lowercased()

                if lowercasedText.contains("error") {
                    logger.error("mpv[\(component)] \(text)")
                } else if lowercasedText.contains("warn") || lowercasedText.contains("warning") {
                    logger.warning("mpv[\(component)] \(text)")
                }
            }

        default:
            break
        }
    }

    private func refreshProperty(named name: String) {
        guard let handle = mpv else { return }

        switch name {
        case "duration":
            var value = 0.0
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0 {
                currentDuration = value
                notifyPosition()
            }

        case "time-pos":
            var value = 0.0
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0 {
                currentPosition = value
                let now = CFAbsoluteTimeGetCurrent()
                if isSeeking || now - lastProgressUpdateTime >= 1 {
                    lastProgressUpdateTime = now
                    notifyPosition()
                }
            }

        case "pause":
            var value: Int32 = 0
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &value) >= 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangePause: value != 0)
                }
            }

        case "paused-for-cache":
            var value: Int32 = 0
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &value) >= 0 {
                notifyLoading(value != 0)
            }

        case "video-params/w", "video-params/h":
            notifyVideoSize(handle: handle)

        default:
            break
        }
    }

    private func notifyPosition() {
        let position = currentPosition
        let duration = currentDuration

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didUpdatePosition: position, duration: duration)
        }
    }

    private func notifyLoading(_ loading: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeLoading: loading)
        }
    }

    private func notifyVideoSize(handle: OpaquePointer) {
        var width: Int64 = 0
        var height: Int64 = 0

        guard getProperty(handle: handle, name: "video-params/w", format: MPV_FORMAT_INT64, value: &width) >= 0,
              getProperty(handle: handle, name: "video-params/h", format: MPV_FORMAT_INT64, value: &height) >= 0,
              width > 0,
              height > 0
        else {
            return
        }

        let size = CGSize(width: Int(width), height: Int(height))
        logger.info(
            "MPV video size changed",
            metadata: [
                "width": "\(Int(width))",
                "height": "\(Int(height))",
            ]
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeVideoSize: size)
        }
    }

    private func notifyFailure(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didFail: message)
        }
    }

    private func command(_ handle: OpaquePointer, _ args: [String]) {
        _ = withCStringArray(args) { pointer in
            mpv_command_async(handle, 0, pointer)
        }
    }

    @discardableResult
    private func commandSync(_ handle: OpaquePointer, _ args: [String]) -> Int32 {
        withCStringArray(args) { pointer in
            mpv_command(handle, pointer)
        }
    }

    private func checkError(_ status: Int32) {
        if status < 0 {
            notifyFailure("MPV API error: \(String(cString: mpv_error_string(status)))")
        }
    }

    @discardableResult
    private func getProperty<T>(handle: OpaquePointer, name: String, format: mpv_format, value: inout T) -> Int32 {
        withUnsafeMutablePointer(to: &value) { pointer in
            mpv_get_property(handle, name, format, pointer)
        }
    }

    private func withCStringArray<R>(_ args: [String], body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cStrings.append(nil)

        defer {
            for pointer in cStrings where pointer != nil {
                free(pointer)
            }
        }

        return cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { pointer in
                body(UnsafeMutablePointer(mutating: pointer))
            }
        }
    }
}

private extension UIColor {

    var mpvHexColor: String {
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return String(
            format: "#%02X%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255),
            Int(alpha * 255)
        )
    }
}

private extension String {

    var escapedMPVHeaderValue: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
