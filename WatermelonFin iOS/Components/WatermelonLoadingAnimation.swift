//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// The caller owns the background and dismissal. Playback never waits for this
/// animation: removing the loading view removes its timeline immediately.
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

    static let launchDuration = 3.8
    private static let playbackDuration = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active || didFinish)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let progress = style == .launch
                ? min(1, elapsed / Self.launchDuration)
                : elapsed.truncatingRemainder(dividingBy: Self.playbackDuration) / Self.playbackDuration
            WatermelonBrandFrame(progress: progress, style: style, reduceMotion: reduceMotion)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            startedAt = Date()
            guard style == .launch, !didFinish else { return }
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.3 : Self.launchDuration))
                try Task.checkCancellation()
                finishLaunch()
            } catch {
                // SwiftUI cancels this task when its owner removes the overlay.
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { finishLaunch() }
        }
    }

    private func finishLaunch() {
        guard style == .launch, !didFinish else { return }
        didFinish = true
        onFinished?()
    }
}

/// The exact, deterministic frame used by the live timeline and image previews.
/// Asset injection also lets previews render the original artwork outside an app bundle.
struct WatermelonBrandFrame: View {
    let progress: Double
    let style: WatermelonLoadingAnimation.Style
    var reduceMotion = false
    var mark: Image = .init("watermelonfin-mark")
    var wordmark: Image = .init("watermelonfin-wordmark")

    private var phase: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        GeometryReader { geometry in
            if style == .launch {
                launchFrame(size: geometry.size)
            } else {
                playbackFrame(size: geometry.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func launchFrame(size: CGSize) -> some View {
        let markSide = min(326, size.height * 0.77, size.width * 0.96)
        let wordWidth = min(320, size.width * 0.96)
        let lettering = reduceMotion ? 1 : ease(phase, from: 0.86, to: 0.94)

        return VStack(spacing: 18) {
            Group {
                if reduceMotion {
                    mark.resizable().interpolation(.high).scaledToFit()
                } else {
                    WatermelonSliceSequence(progress: phase, mark: mark)
                }
            }
            .frame(width: markSide, height: markSide)

            wordmark
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: wordWidth, height: wordWidth * 41 / 304)
                .opacity(lettering)
                .offset(y: 8 * (1 - lettering))
        }
        .frame(width: size.width, height: size.height)
    }

    private func playbackFrame(size: CGSize) -> some View {
        let side = min(size.width, size.height, 112)
        let wave = reduceMotion ? 0 : sin(phase * .pi * 2)
        // The reflection clears completely before wrapping, so there is no flash
        // or visual reset at the loop boundary. The inset play stays red.
        let reflection = reduceMotion ? 0 : pow(sin(phase * .pi), 2) * 0.16
        return reflectedMark(side: side, position: phase, intensity: reflection)
            .scaleEffect(1 + 0.012 * wave)
            .rotation3DEffect(.degrees(2.2 * wave), axis: (x: 0, y: 1, z: 0), perspective: 0.2)
            .frame(width: size.width, height: size.height)
    }

    private func reflectedMark(side: CGFloat, position: Double, intensity: Double) -> some View {
        mark
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: side, height: side)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.18), location: 0.34),
                        .init(color: .white, location: 0.50),
                        .init(color: .white.opacity(0.16), location: 0.60),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: side * 0.24, height: side * 1.8)
                .rotationEffect(.degrees(24))
                .offset(x: side * (position * 2 - 1))
                .frame(width: side, height: side)
                .mask {
                    mark.resizable().scaledToFit().frame(width: side, height: side)
                }
                .opacity(intensity)
                .blendMode(.screen)
            }
    }

    private func ease(_ value: Double, from start: Double, to end: Double) -> Double {
        let t = min(1, max(0, (value - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }
}

/// Six persistent pieces, first joined as two shell halves. Faces change only
/// at an edge-on rotation; no opacity dissolve or travelling reveal mask is used.
private struct WatermelonSliceSequence: View {
    let progress: Double
    let mark: Image

    private var heroTurn: Double { ease(progress, from: 0.67, to: 0.84) }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Canvas { context, size in
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    context.scaleBy(x: side * 0.39, y: side * 0.39)
                    drawSequence(in: context)
                }
                // The artwork is the reverse face of the selected wedge. At
                // 90 degrees both faces have zero width, hiding the face change.
                if heroTurn >= 0.5 {
                    mark.resizable().interpolation(.high).scaledToFit()
                        .frame(width: side, height: side)
                        .scaleEffect(x: -cos(heroTurn * .pi), y: 0.78 + 0.22 * heroTurn)
                        .rotationEffect(.degrees(-7 * (1 - heroTurn)))
                }
            }
        }
    }

    private func drawSequence(in context: GraphicsContext) {
        let split = ease(progress, from: 0.13, to: 0.23)
        let turn = ease(progress, from: 0.26, to: 0.43)
        let cut = ease(progress, from: 0.50, to: 0.555)
        let depart = ease(progress, from: 0.62, to: 0.80)
        let collect = ease(progress, from: 0.60, to: 0.69)

        if split == 0 {
            drawShell(in: context)
        } else if progress < 0.50 {
            for half in 0..<2 {
                let direction = half == 0 ? 1.0 : -1.0
                var face = context
                face.translateBy(x: 0, y: direction * 0.26 * split)
                // Rotate around the centre of each physical half, not the fruit.
                let pivot = direction * 0.43
                face.translateBy(x: 0, y: pivot)
                face.scaleBy(x: 1, y: max(0.002, abs(cos(.pi * turn))))
                face.translateBy(x: 0, y: -pivot)
                let shape = sector(start: Double(half) * .pi, sweep: .pi, radius: 1)
                if turn < 0.5 {
                    face.clip(to: shape)
                    drawShell(in: face)
                } else {
                    drawFlesh(in: face, start: Double(half) * .pi, sweep: .pi, seams: false)
                }
            }
        } else {
            // Three wedges in each half. They retain their positions and faces
            // through the cut; the five companions physically leave the canvas.
            for index in [0, 1, 2, 4, 5, 3] {
                let start = Double(index) * .pi / 3
                let angle = start + .pi / 6
                let direction = index < 3 ? 1.0 : -1.0
                let centre = CGPoint(x: cos(angle) * 0.62, y: sin(angle) * 0.62)
                var wedge = context
                let spread = 0.19 * cut
                let originX = cos(angle) * spread
                let originY = direction * 0.26 + sin(angle) * spread
                if index == 3 {
                    guard heroTurn < 0.5 else { continue }
                    wedge.translateBy(
                        x: (originX + centre.x) * (1 - collect),
                        y: (originY + centre.y) * (1 - collect)
                    )
                    wedge.scaleBy(x: cos(heroTurn * .pi) * (1 + 1.15 * collect), y: 1 + 1.15 * collect)
                    wedge.rotate(by: .degrees(-30 * collect))
                    wedge.translateBy(x: -centre.x, y: -centre.y)
                } else {
                    wedge.translateBy(
                        x: originX + cos(angle) * 5 * depart,
                        y: originY + sin(angle) * 5 * depart
                    )
                    wedge.translateBy(x: centre.x, y: centre.y)
                    wedge.rotate(by: .degrees((index.isMultiple(of: 2) ? 1 : -1) * 68 * depart))
                    wedge.translateBy(x: -centre.x, y: -centre.y)
                }
                drawFlesh(in: wedge, start: start, sweep: .pi / 3, seams: true)
            }
        }

        // The knife actions are brief hard-edged strokes followed immediately
        // by separation. These are accents, never masks that reveal new artwork.
        if progress >= 0.115, progress < 0.17 {
            let travel = ease(progress, from: 0.115, to: 0.145)
            var line = Path()
            line.move(to: CGPoint(x: -1.12, y: 0))
            line.addLine(to: CGPoint(x: -1.12 + 2.24 * travel, y: 0))
            context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 0.015, lineCap: .round))
        }
        if progress >= 0.49, progress < 0.525 {
            for angle in [Double.pi / 3, Double.pi * 2 / 3] {
                var line = Path()
                line.move(to: CGPoint(x: -cos(angle), y: -sin(angle) - 0.26))
                line.addLine(to: CGPoint(x: cos(angle), y: sin(angle) + 0.26))
                context.stroke(line, with: .color(.white.opacity(0.9)), lineWidth: 0.012)
            }
        }
    }

    private func sector(start: Double, sweep: Double, radius: Double) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addArc(center: .zero, radius: radius, startAngle: .radians(start), endAngle: .radians(start + sweep), clockwise: false)
        path.closeSubpath()
        return path
    }

    private func drawFlesh(in context: GraphicsContext, start: Double, sweep: Double, seams: Bool) {
        let rind = sector(start: start, sweep: sweep, radius: 1)
        let pith = sector(start: start, sweep: sweep, radius: 0.92)
        let flesh = sector(start: start, sweep: sweep, radius: 0.85)
        // A small extruded green edge keeps the slices solid during rotation.
        var edge = context
        edge.translateBy(x: 0.015, y: 0.045)
        edge.fill(rind, with: .color(Color(red: 0.09, green: 0.28, blue: 0.04)))
        context.fill(rind, with: .linearGradient(
            Gradient(colors: [Color(red: 0.48, green: 0.73, blue: 0.12), Color(red: 0.12, green: 0.39, blue: 0.04)]),
            startPoint: .init(x: -1, y: -1), endPoint: .init(x: 1, y: 1)
        ))
        context.fill(pith, with: .color(Color(red: 0.96, green: 0.95, blue: 0.70)))
        context.fill(flesh, with: .linearGradient(
            Gradient(colors: [Color(red: 1, green: 0.32, blue: 0.39), Color(red: 0.87, green: 0.035, blue: 0.17)]),
            startPoint: .init(x: -0.7, y: -0.8), endPoint: .init(x: 0.8, y: 1)
        ))
        // A polished outer bevel catches light in the same pink as the logo.
        var polished = context
        polished.clip(to: flesh)
        polished.stroke(flesh, with: .color(Color(red: 1, green: 0.55, blue: 0.60).opacity(0.65)), lineWidth: 0.10)
        for facet in 0..<6 {
            let angle = Double(facet) * .pi / 3
            var plane = Path()
            plane.move(to: .init(x: -0.12, y: -0.18))
            plane.addLine(to: .init(x: cos(angle) * 0.85, y: sin(angle) * 0.85))
            plane.addLine(to: .init(x: cos(angle + 0.5) * 0.85, y: sin(angle + 0.5) * 0.85))
            plane.closeSubpath()
            polished.fill(plane, with: .color(.white.opacity(facet.isMultiple(of: 2) ? 0.055 : 0.018)))
        }
        context.stroke(flesh, with: .color(Color(red: 1, green: 0.56, blue: 0.60)), lineWidth: 0.022)
        if seams {
            context.stroke(rind, with: .color(Color(red: 1, green: 0.92, blue: 0.71).opacity(0.75)), lineWidth: 0.009)
        }
        // Seed positions are shared by the halves and the six sectors, so the
        // cut never changes their arrangement or makes the fruit jump.
        for index in 0..<12 {
            let angle = (Double(index) + 0.5) * .pi / 6
            guard angle >= start, angle < start + sweep else { continue }
            var seed = context
            seed.translateBy(x: cos(angle) * 0.66, y: sin(angle) * 0.66)
            seed.rotate(by: .radians(angle - .pi / 2))
            let oval = Path(ellipseIn: CGRect(x: -0.027, y: -0.052, width: 0.054, height: 0.104))
            seed.fill(oval, with: .color(Color(red: 0.14, green: 0.095, blue: 0.065)))
            seed.stroke(oval, with: .color(Color(red: 1, green: 0.55, blue: 0.53).opacity(0.7)), lineWidth: 0.008)
            seed.fill(Path(ellipseIn: CGRect(x: -0.014, y: -0.038, width: 0.012, height: 0.035)), with: .color(.white.opacity(0.25)))
        }
    }

    private func drawShell(in context: GraphicsContext) {
        let outline = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
        var fruit = context
        fruit.clip(to: outline)
        fruit.fill(outline, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.47, green: 0.74, blue: 0.29), location: 0),
                .init(color: Color(red: 0.19, green: 0.47, blue: 0.10), location: 0.43),
                .init(color: Color(red: 0.035, green: 0.19, blue: 0.08), location: 0.80),
                .init(color: Color(red: 0.012, green: 0.07, blue: 0.04), location: 1),
            ]),
            center: CGPoint(x: -0.32, y: -0.43), startRadius: 0, endRadius: 1.65
        ))

        for offset in [-0.58, -0.30, 0.05, 0.39, 0.65] {
            var stripe = Path()
            stripe.move(to: CGPoint(x: offset * 0.27, y: -0.95))
            stripe.addCurve(
                to: CGPoint(x: offset * 0.32, y: 0.95),
                control1: CGPoint(x: offset - 0.24, y: -0.40),
                control2: CGPoint(x: offset - 0.18, y: 0.40)
            )
            stripe.addCurve(
                to: CGPoint(x: offset * 0.27 + 0.045, y: -0.95),
                control1: CGPoint(x: offset + 0.07, y: 0.38),
                control2: CGPoint(x: offset + 0.08, y: -0.40)
            )
            stripe.closeSubpath()
            fruit.fill(stripe, with: .linearGradient(
                Gradient(colors: [Color(red: 0.07, green: 0.27, blue: 0.08).opacity(0.75), .black.opacity(0.20)]),
                startPoint: CGPoint(x: -0.6, y: -0.7), endPoint: CGPoint(x: 0.5, y: 0.7)
            ))
        }

        // Broad translucent planes give the glossy rind a cut-glass depth.
        let facets: [[CGPoint]] = [
            [.init(x: -0.8, y: -0.45), .init(x: -0.22, y: -0.86), .init(x: -0.38, y: 0.12)],
            [.init(x: -0.22, y: -0.86), .init(x: 0.46, y: -0.66), .init(x: 0.13, y: -0.12)],
            [.init(x: 0.13, y: -0.12), .init(x: 0.73, y: -0.32), .init(x: 0.54, y: 0.58)],
            [.init(x: -0.62, y: 0.42), .init(x: 0.13, y: -0.12), .init(x: -0.06, y: 0.87)],
        ]
        for (index, vertices) in facets.enumerated() {
            var plane = Path()
            plane.addLines(vertices)
            plane.closeSubpath()
            fruit.fill(plane, with: .color(.white.opacity(index == 0 ? 0.09 : 0.035)))
        }

        var specular = Path()
        specular.move(to: CGPoint(x: -0.63, y: 0.05))
        specular.addCurve(
            to: CGPoint(x: 0.16, y: -0.78),
            control1: CGPoint(x: -0.73, y: -0.60), control2: CGPoint(x: -0.22, y: -0.91)
        )
        var bloom = fruit
        bloom.addFilter(.blur(radius: 0.025))
        bloom.stroke(specular, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 0.075, lineCap: .round))
        fruit.stroke(specular, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.05), .white.opacity(0.6), .white.opacity(0.08)]),
            startPoint: CGPoint(x: -0.65, y: -0.2), endPoint: CGPoint(x: 0.2, y: -0.8)
        ), style: StrokeStyle(lineWidth: 0.014, lineCap: .round))
        fruit.stroke(outline, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.45), Color.green.opacity(0.08), Color(red: 0.42, green: 0.68, blue: 0.23).opacity(0.35)]),
            startPoint: CGPoint(x: -0.65, y: -0.8), endPoint: CGPoint(x: 0.65, y: 0.8)
        ), lineWidth: 0.014)
    }

    private func ease(_ value: Double, from start: Double, to end: Double) -> Double {
        let t = min(1, max(0, (value - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }
}

#Preview("Launch") {
    WatermelonLoadingAnimation(style: .launch)
        .frame(width: 360, height: 420)
        .background(Color(red: 0.015, green: 0.045, blue: 0.028))
}

#Preview("Brand hold") {
    WatermelonBrandFrame(progress: 1, style: .launch)
        .frame(width: 360, height: 420)
        .background(Color(red: 0.015, green: 0.045, blue: 0.028))
}

#Preview("Playback") {
    WatermelonLoadingAnimation(style: .playback)
        .frame(width: 112, height: 112)
        .background(Color.black)
}
