//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Pulse
import SwiftUI

struct DiagnosticsView: View {

    @Router
    private var router

    @StateObject
    private var viewModel = SettingsViewModel()

    var body: some View {
        Form(systemImage: "wrench.and.screwdriver") {
            appSection
            connectionSection

            #if DEBUG || !os(tvOS)
            logsSection
            #endif
        }
        .navigationTitle(L10n.diagnostics)
    }

    private var appSection: some View {
        Section("WatermelonFin") {
            LabeledContent(
                L10n.version,
                value: AppBuildInfo.current.versionDisplay
            )
            .focusable(false)

            LabeledContent {
                Text(AppBuildInfo.current.commitDisplay)
            } label: {
                Text(verbatim: "Commit")
            }
            .focusable(false)
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        if let session = viewModel.userSession {
            Section {
                LabeledContent(
                    L10n.name,
                    value: session.server.name
                )
                .focusable(false)

                LabeledContent(
                    L10n.currentServerAddress,
                    value: session.server.currentURL.absoluteString
                )
                .focusable(false)
            } header: {
                Text(L10n.server)
            } footer: {
                Text(L10n.diagnosticsDescription)
            }
        }
    }

    #if DEBUG || !os(tvOS)
    private var logsSection: some View {
        Section(L10n.advancedAndDiagnostics) {
            ChevronButton(
                L10n.advancedLogs,
                subtitle: L10n.advancedLogsDescription
            ) {
                router.route(to: .log)
            }
        }
    }
    #endif
}

#if os(tvOS)
struct LocalizedLogView: View {

    @StateObject
    private var viewModel = LocalizedLogViewModel()

    @State
    private var isPresentingRemoveLogs = false

    var body: some View {
        HStack(spacing: 0) {
            logList
                .frame(maxWidth: .infinity)

            SwiftUI.Form {
                filterSection
                storeSection
                actionSection
            }
            .frame(width: 620)
            .padding(.top)
            .backport
            .scrollClipDisabled()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(L10n.advancedLogs)
        .onAppear(perform: viewModel.refresh)
        .onReceive(viewModel.store.events.receive(on: DispatchQueue.main)) { _ in
            viewModel.refresh()
        }
        .confirmationDialog(
            L10n.removeLogs,
            isPresented: $isPresentingRemoveLogs
        ) {
            Button(L10n.removeAll, role: .destructive) {
                viewModel.removeLogs()
            }

            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.removeLogsConfirmation)
        }
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if viewModel.filteredEntries.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.filteredEntries) { entry in
                        Button {} label: {
                            LocalizedLogEntryRow(entry: entry)
                        }
                        .buttonStyle(.platformCard)
                    }
                }
            }
            .edgePadding()
        }
        .backport
        .scrollClipDisabled()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(L10n.noLogs)
                .font(.title2.weight(.semibold))

            Text(L10n.noLogsDescription)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private var filterSection: some View {
        Section(L10n.quickFilters) {
            LogFilterButton(
                title: L10n.errorsOnly,
                systemImage: "exclamationmark.octagon",
                isOn: $viewModel.isShowingErrorsOnly
            )

            LogFilterButton(
                title: L10n.networkOnly,
                systemImage: "arrow.down.circle",
                isOn: $viewModel.isShowingNetworkOnly
            )
        }
    }

    private var storeSection: some View {
        Section(L10n.storeInfo) {
            LabeledContent(
                L10n.logEntries,
                value: String(viewModel.allEntries.count)
            )
            .focusable(false)

            LabeledContent(
                L10n.networkRequests,
                value: String(viewModel.networkEntryCount)
            )
            .focusable(false)

            LabeledContent(
                L10n.appMessages,
                value: String(viewModel.messageEntryCount)
            )
            .focusable(false)
        }
    }

    private var actionSection: some View {
        Section(L10n.logs) {
            Button {
                viewModel.refresh()
            } label: {
                Label(L10n.refresh, systemImage: "arrow.clockwise")
            }

            Button(role: .destructive) {
                isPresentingRemoveLogs = true
            } label: {
                Label(L10n.removeLogs, systemImage: "trash")
            }
        }
    }
}

private struct LogFilterButton: View {

    @FocusState
    private var isFocused: Bool

    let title: String
    let systemImage: String

    @Binding
    var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(isFocused ? .black : .primary)

                Spacer()

                Text(isOn ? L10n.enabled : L10n.disabled)
                    .fontWeight(.medium)
                    .foregroundStyle(isFocused ? .black : .secondary)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isFocused ? .black : .secondary)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? Color.white : Color.clear)
            }
            .animation(.easeInOut(duration: 0.125), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .listRowInsets(.zero)
        .accessibilityValue(isOn ? L10n.enabled : L10n.disabled)
    }
}

private struct LocalizedLogEntryRow: View {

    let entry: LocalizedLogViewModel.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(entry.statusTitle, systemImage: entry.systemImage)
                    .font(.headline)
                    .foregroundStyle(entry.tintColor)
                    .lineLimit(1)

                Spacer()

                Text(entry.timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(entry.primaryText)
                .font(.body.monospaced())
                .lineLimit(2)

            if entry.detailText.isNotEmpty {
                Text(entry.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
    }
}

@MainActor
final class LocalizedLogViewModel: ObservableObject {

    struct Entry: Identifiable {

        enum Kind {
            case message
            case network
        }

        let id: String
        let kind: Kind
        let createdAt: Date
        let statusTitle: String
        let systemImage: String
        let tintColor: Color
        let primaryText: String
        let detailText: String
        let isError: Bool

        var timeText: String {
            Self.timeFormatter.string(from: createdAt)
        }

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    let store: LoggerStore

    @Published
    var allEntries: [Entry] = []
    @Published
    var isShowingErrorsOnly = false
    @Published
    var isShowingNetworkOnly = true

    init(store: LoggerStore = .shared) {
        self.store = store
        refresh()
    }

    var filteredEntries: [Entry] {
        allEntries.filter { entry in
            if isShowingNetworkOnly, entry.kind != .network {
                return false
            }

            if isShowingErrorsOnly, !entry.isError {
                return false
            }

            return true
        }
    }

    var messageEntryCount: Int {
        allEntries.filter { $0.kind == .message }.count
    }

    var networkEntryCount: Int {
        allEntries.filter { $0.kind == .network }.count
    }

    func refresh() {
        let tasks = (try? store.tasks(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)])) ?? []
        let messages = (try? store.messages(
            sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
            predicate: NSPredicate(format: "task == NULL")
        )) ?? []

        allEntries = (
            tasks.map(Self.entry(for:)) +
                messages.map(Self.entry(for:))
        )
        .sorted { $0.createdAt > $1.createdAt }
    }

    func removeLogs() {
        store.removeAll()
        allEntries.removeAll()
    }

    private static func entry(for task: NetworkTaskEntity) -> Entry {
        let url = task.url.flatMap(URL.init(string:))
        let path = url.map { url in
            url.path.isEmpty ? "/" : url.path
        } ?? task.url ?? String.emptyDash
        let method = task.httpMethod ?? "GET"
        let isCancelled = isCancelled(task)
        let isError = !isCancelled && (task.state == .failure || task.statusCode >= 400)
        let statusTitle = statusTitle(for: task)
        let detailText = [
            task.host,
            formattedSize(for: task),
            formattedDuration(task.duration),
        ]
            .compactMap { $0 }
            .joined(separator: " · ")

        return Entry(
            id: task.objectID.uriRepresentation().absoluteString,
            kind: .network,
            createdAt: task.createdAt,
            statusTitle: statusTitle,
            systemImage: systemImage(for: task, isCancelled: isCancelled, isError: isError),
            tintColor: tintColor(isCancelled: isCancelled, isError: isError),
            primaryText: "\(method) \(path)",
            detailText: detailText,
            isError: isError
        )
    }

    private static func entry(for message: LoggerMessageEntity) -> Entry {
        let level = LoggerStore.Level(rawValue: message.level) ?? .debug

        return Entry(
            id: message.objectID.uriRepresentation().absoluteString,
            kind: .message,
            createdAt: message.createdAt,
            statusTitle: localizedTitle(for: level),
            systemImage: systemImage(for: level),
            tintColor: tintColor(for: level),
            primaryText: message.text,
            detailText: message.label == "default" ? "" : message.label,
            isError: level >= .error
        )
    }

    private static func statusTitle(for task: NetworkTaskEntity) -> String {
        switch task.state {
        case .pending:
            return L10n.pending
        case .success:
            if task.statusCode == 0 {
                return L10n.success
            } else {
                return localizedStatusTitle(for: task.statusCode)
            }
        case .failure:
            if isCancelled(task) {
                return L10n.taskCancelled
            } else if task.statusCode != 0 {
                return localizedStatusTitle(for: task.statusCode)
            } else {
                return L10n.failed
            }
        }
    }

    private static func localizedStatusTitle(for statusCode: Int32) -> String {
        let code = Int(statusCode)

        if (200 ..< 300).contains(code) {
            return "\(code) \(L10n.success)"
        }

        if code == 401 {
            return "\(code) \(L10n.unauthorized)"
        }

        if (400 ..< 600).contains(code) {
            return "\(code) \(L10n.failed)"
        }

        return "\(code) \(HTTPURLResponse.localizedString(forStatusCode: code).localizedCapitalized)"
    }

    private static func isCancelled(_ task: NetworkTaskEntity) -> Bool {
        guard let errorDescription = task.errorDebugDescription else { return false }
        return errorDescription.localizedCaseInsensitiveContains("Code=-999") ||
            errorDescription.localizedCaseInsensitiveContains("cancelled")
    }

    private static func systemImage(
        for task: NetworkTaskEntity,
        isCancelled: Bool,
        isError: Bool
    ) -> String {
        if isCancelled {
            return "xmark.circle"
        }

        if isError {
            return "xmark.octagon.fill"
        }

        return "network"
    }

    private static func tintColor(
        isCancelled: Bool,
        isError: Bool
    ) -> Color {
        if isCancelled {
            return .secondary
        }

        return isError ? .red : .green
    }

    private static func formattedSize(for task: NetworkTaskEntity) -> String? {
        let size = task.responseBodySize > 0 ? task.responseBodySize : task.requestBodySize
        guard size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String? {
        guard duration > 0 else { return nil }

        if duration < 1 {
            return "\(Int(duration * 1000)) ms"
        }

        return String(format: "%.1f s", duration)
    }

    private static func localizedTitle(for level: LoggerStore.Level) -> String {
        switch level {
        case .trace:
            return L10n.trace
        case .debug:
            return L10n.debug
        case .info:
            return L10n.info
        case .notice:
            return L10n.notice
        case .warning:
            return L10n.warning
        case .error:
            return L10n.error
        case .critical:
            return L10n.critical
        }
    }

    private static func systemImage(for level: LoggerStore.Level) -> String {
        switch level {
        case .trace, .debug:
            return "curlybraces.square"
        case .info, .notice:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error, .critical:
            return "xmark.octagon.fill"
        }
    }

    private static func tintColor(for level: LoggerStore.Level) -> Color {
        switch level {
        case .trace, .debug:
            return .secondary
        case .info, .notice:
            return .blue
        case .warning:
            return .orange
        case .error, .critical:
            return .red
        }
    }
}
#endif
