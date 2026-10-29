//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct QuickConnectView: View {

    @Router
    private var router

    @ObservedObject
    private var viewModel: QuickConnect

    private let retry: () -> Void

    init(quickConnect: QuickConnect, retry: @escaping () -> Void) {
        self.viewModel = quickConnect
        self.retry = retry
    }

    private func pollingView(code: String) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                BulletedList(spacing: 16) {
                    Text(L10n.quickConnectStep1).fixedSize(horizontal: false, vertical: true)

                    Text(L10n.quickConnectStep2).fixedSize(horizontal: false, vertical: true)

                    Text(L10n.quickConnectStep3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(code)
                    .tracking(10)
                    .font(.largeTitle)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel(code)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("signIn.quickConnect.instructions")
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .authenticated, .idle, .retrievingCode:
                ProgressView()
            case let .polling(code):
                pollingView(code: code)
            case let .error(error):
                #if os(iOS)
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text(L10n.quickConnectUnavailable)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L10n.retry, action: retry)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("signIn.quickConnect.retry")
                    }
                    .padding()
                    .padding(.top, 24)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                #else
                VStack(spacing: 20) {
                    ErrorView(error: error)
                    Button(L10n.retry, action: retry)
                        .buttonStyle(.primary)
                        .frame(width: 320, height: 64)
                        .accessibilityIdentifier("signIn.quickConnect.retry")
                }
                .padding()
                .frame(maxWidth: 640)
                #endif
            }
        }
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .edgePadding()
        .navigationTitle(L10n.quickConnect)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarCloseButton {
                router.dismiss()
            }
        #endif
            .onFirstAppear {
                    viewModel.start()
                }
                .onDisappear {
                    viewModel.stop()
                }
    }
}
