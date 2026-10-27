//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// Initialize the real application behind a bounded, once-per-window launch animation.
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
                .allowsHitTesting(!isLaunching)
                .accessibilityHidden(isLaunching)

            if isLaunching {
                ZStack {
                    Color(red: 0.015, green: 0.045, blue: 0.028)
                        .ignoresSafeArea()
                    WatermelonLoadingAnimation(style: .launch, onFinished: finish)
                        .frame(maxWidth: 420, maxHeight: 420)
                        .padding(32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("WatermelonFin")
                .accessibilityIdentifier("mobile.launch.animation")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Do not resume or replay a splash when returning to an existing session.
            if phase == .background { isLaunching = false }
        }
    }

    private func finish() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.22)) {
            isLaunching = false
        }
    }
}
