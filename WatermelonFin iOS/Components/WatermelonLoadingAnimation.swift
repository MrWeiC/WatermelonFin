//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// A procedural watermelon-to-play mark. The caller owns the launch background
/// and its dismissal, and can remove the playback mark as soon as media is ready.
struct WatermelonLoadingAnimation: View {

    enum Style {
        case launch
        case playback
    }

    let style: Style
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.scenePhase)
    private var scenePhase

    @State
    private var startedAt = Date()
    @State
    private var didFinish = false

    private static let launchDuration = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active || didFinish)) { timeline in
            Canvas { context, size in
                let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                let dimension = min(size.width, size.height, style == .launch ? 224 : 100)
                context.translateBy(x: size.width / 2, y: size.height / 2)
                context.scaleBy(x: dimension / 2, y: dimension / 2)

                if reduceMotion {
                    WatermelonMark.drawSlice(in: context, morph: 0, white: 0)
                } else if style == .launch {
                    WatermelonMark.drawLaunch(in: context, progress: min(1, elapsed / Self.launchDuration))
                } else {
                    WatermelonMark.drawPlayback(in: context, elapsed: elapsed)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            startedAt = Date()
            guard style == .launch, !didFinish else { return }
            // This task is cancelled automatically when the view disappears.
            // Finishing never depends on an animation frame or a repeating timer.
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.3 : Self.launchDuration))
                try Task.checkCancellation()
                finishLaunch()
            } catch {
                // A removed launch overlay must not call back into its owner.
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                finishLaunch()
            }
        }
    }

    private func finishLaunch() {
        guard style == .launch, !didFinish else { return }
        didFinish = true
        onFinished?()
    }
}

/// All paths use a two-unit coordinate space, so rotation and resizing preserve
/// the same silhouette on a phone, tablet, or a changing multitasking window.
private enum WatermelonMark {

    private static let rind = Color(red: 0.13, green: 0.54, blue: 0.28)
    private static let rindLight = Color(red: 0.39, green: 0.76, blue: 0.37)
    private static let pith = Color(red: 0.87, green: 0.96, blue: 0.66)
    private static let flesh = Color.watermelonRed
    private static let seed = Color(red: 0.16, green: 0.06, blue: 0.10)

    static func drawLaunch(in context: GraphicsContext, progress t: Double) {
        let entrance = smooth(t, from: 0, to: 0.12)
        let split = smooth(t, from: 0.36, to: 0.61)
        let melonOpacity = 1 - smooth(t, from: 0.43, to: 0.65)

        var glow = context
        glow.opacity = 0.15 * entrance * (1 - smooth(t, from: 0.7, to: 0.98))
        glow.addFilter(.blur(radius: 0.22))
        glow.fill(Path(ellipseIn: CGRect(x: -0.55, y: -0.42, width: 1.1, height: 1.1)), with: .color(flesh))

        if melonOpacity > 0 {
            let scale = 0.87 + 0.13 * entrance
            // Two clipped copies separate along the normal of the diagonal cut.
            for side in [-1.0, 1.0] {
                var half = context
                half.opacity = entrance * melonOpacity
                half.translateBy(x: -side * 0.14 * split, y: side * 0.21 * split)
                half.rotate(by: .degrees(side * 13 * split))
                half.scaleBy(x: scale, y: scale)
                var clip = Path()
                clip.move(to: CGPoint(x: -2, y: -1.3))
                clip.addLine(to: CGPoint(x: 2, y: 1.3))
                clip.addLine(to: CGPoint(x: 2, y: side * 3))
                clip.addLine(to: CGPoint(x: -2, y: side * 3))
                clip.closeSubpath()
                half.clip(to: clip)
                drawMelon(in: half)
            }
        }

        let slashIn = smooth(t, from: 0.29, to: 0.43)
        let slashOut = smooth(t, from: 0.44, to: 0.56)
        if slashIn > 0, slashOut < 1 {
            var slash = context
            slash.opacity = (1 - slashOut) * 0.95
            let start = CGPoint(x: -1.05 + 2.1 * slashOut, y: -0.69 + 1.38 * slashOut)
            let end = CGPoint(x: -1.05 + 2.1 * slashIn, y: -0.69 + 1.38 * slashIn)
            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            var bloom = slash
            bloom.addFilter(.blur(radius: 0.05))
            bloom.stroke(line, with: .color(pith), style: StrokeStyle(lineWidth: 0.065, lineCap: .round))
            slash.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 0.018, lineCap: .round))
        }

        let reveal = smooth(t, from: 0.46, to: 0.63)
        if reveal > 0 {
            var slice = context
            slice.opacity = reveal
            let turn = smooth(t, from: 0.48, to: 0.84)
            let scale = 0.65 + 0.35 * reveal
            slice.scaleBy(x: scale, y: scale)
            slice.rotate(by: .degrees(-100 * (1 - turn)))
            drawSlice(
                in: slice,
                morph: smooth(t, from: 0.63, to: 0.88),
                white: smooth(t, from: 0.81, to: 0.96)
            )
        }
    }

    static func drawPlayback(in context: GraphicsContext, elapsed: Double) {
        // A quiet, continuous slice/play loop without a discontinuous reset.
        let wave = (1 - cos(elapsed * .pi * 2 / 1.7)) / 2
        let morph = smooth(wave, from: 0.12, to: 0.88)
        var mark = context
        let scale = 0.90 + 0.045 * sin(elapsed * .pi * 2 / 1.7)
        mark.scaleBy(x: scale, y: scale)
        mark.rotate(by: .degrees(-8 * (1 - morph)))
        drawSlice(in: mark, morph: morph, white: morph * 0.92)
    }

    private static func drawMelon(in context: GraphicsContext) {
        let bounds = CGRect(x: -0.73, y: -0.78, width: 1.46, height: 1.56)
        let body = Path(ellipseIn: bounds)
        var melon = context
        melon.clip(to: body)
        melon.fill(body, with: .linearGradient(
            Gradient(colors: [rindLight, rind, Color(red: 0.025, green: 0.22, blue: 0.13)]),
            startPoint: CGPoint(x: -0.5, y: -0.65), endPoint: CGPoint(x: 0.65, y: 0.7)
        ))

        // Longitudinal, tapered stripes describe a round fruit without an icon asset.
        for offset in [-0.58, -0.28, 0.08, 0.42] {
            var stripe = Path()
            stripe.move(to: CGPoint(x: offset * 0.32, y: -0.84))
            stripe.addCurve(
                to: CGPoint(x: offset * 0.30, y: 0.86),
                control1: CGPoint(x: offset - 0.22, y: -0.35),
                control2: CGPoint(x: offset - 0.16, y: 0.38)
            )
            stripe.addCurve(
                to: CGPoint(x: offset * 0.32 + 0.055, y: -0.84),
                control1: CGPoint(x: offset + 0.09, y: 0.33),
                control2: CGPoint(x: offset + 0.07, y: -0.37)
            )
            stripe.closeSubpath()
            melon.fill(stripe, with: .color(Color(red: 0.03, green: 0.27, blue: 0.12).opacity(0.66)))
        }

        var highlight = melon
        highlight.addFilter(.blur(radius: 0.08))
        highlight.fill(
            Path(ellipseIn: CGRect(x: -0.43, y: -0.61, width: 0.27, height: 0.50)),
            with: .color(Color.white.opacity(0.17))
        )
        context.stroke(body, with: .color(rindLight.opacity(0.35)), lineWidth: 0.012)
    }

    static func drawSlice(in context: GraphicsContext, morph: Double, white: Double) {
        let outer = slicePath(morph: morph, inset: 0)
        let innerRind = slicePath(morph: morph, inset: 0.047 * (1 - morph))
        let interior = slicePath(morph: morph, inset: 0.105 * (1 - morph))

        context.fill(outer, with: .linearGradient(
            Gradient(colors: [rindLight, rind]),
            startPoint: CGPoint(x: -0.8, y: -0.6), endPoint: CGPoint(x: -0.4, y: 0.7)
        ))
        context.fill(innerRind, with: .color(pith))
        context.fill(interior, with: .linearGradient(
            Gradient(colors: [Color(red: 1, green: 0.38, blue: 0.40), flesh, Color(red: 0.84, green: 0.10, blue: 0.26)]),
            startPoint: CGPoint(x: 0.4, y: -0.45), endPoint: CGPoint(x: -0.5, y: 0.5)
        ))

        var seeds = context
        seeds.opacity = 1 - smooth(morph, from: 0.15, to: 0.85)
        let positions: [(Double, Double, Double)] = [
            (-0.40, -0.34, -36), (-0.50, -0.06, -4),
            (-0.39, 0.27, 33), (-0.12, -0.18, -28),
            (-0.10, 0.16, 27), (0.20, 0.00, 90),
        ]
        for (x, y, angle) in positions {
            var dot = seeds
            dot.translateBy(x: x, y: y)
            dot.rotate(by: .degrees(angle))
            var seedPath = Path()
            seedPath.move(to: CGPoint(x: 0, y: -0.055))
            seedPath.addCurve(
                to: CGPoint(x: 0, y: 0.045),
                control1: CGPoint(x: -0.060, y: 0.005), control2: CGPoint(x: -0.030, y: 0.046)
            )
            seedPath.addCurve(
                to: CGPoint(x: 0, y: -0.055),
                control1: CGPoint(x: 0.030, y: 0.046), control2: CGPoint(x: 0.060, y: 0.005)
            )
            dot.fill(seedPath, with: .color(seed))
        }

        var play = context
        play.opacity = white
        play.fill(outer, with: .color(.white))
    }

    private static func slicePath(morph: Double, inset: Double) -> Path {
        // The curved rind straightens into the back edge of the same play triangle.
        let back = -0.48 + inset
        let height = 0.66 - inset * 0.42
        let curve = -1.0 + 0.52 * morph + inset
        var path = Path()
        path.move(to: CGPoint(x: 0.76, y: 0))
        path.addLine(to: CGPoint(x: back, y: height))
        path.addQuadCurve(to: CGPoint(x: back, y: -height), control: CGPoint(x: curve, y: 0))
        path.closeSubpath()
        return path
    }

    private static func smooth(_ value: Double, from start: Double, to end: Double) -> Double {
        let progress = min(1, max(0, (value - start) / (end - start)))
        return progress * progress * (3 - 2 * progress)
    }
}

#Preview("Launch") {
    WatermelonLoadingAnimation(style: .launch)
        .frame(width: 300, height: 300)
        .background(Color(red: 0.015, green: 0.045, blue: 0.028))
}

#Preview("Playback") {
    WatermelonLoadingAnimation(style: .playback)
        .frame(width: 112, height: 112)
        .background(Color.black)
}
