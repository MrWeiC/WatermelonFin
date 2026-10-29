//
// WatermelonFin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
import UIKit

struct _UnmaskSecureField: View {
    let title: String
    let showsPlaceholder: Bool
    @Binding
    var text: String
    let isFocused: Binding<Bool>?
    let onSubmit: (() -> Void)?
    @State
    private var revealed = false

    init(
        _ title: String,
        text: Binding<String>,
        showsPlaceholder: Bool = true,
        isFocused: Binding<Bool>? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.showsPlaceholder = showsPlaceholder
        _text = text
        self.isFocused = isFocused
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack {
            PasswordTextField(
                title: title, text: $text, revealed: revealed,
                showsPlaceholder: showsPlaceholder,
                isFocused: isFocused, onSubmit: onSubmit
            )
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? L10n.hidePassword : L10n.showPassword)
            .accessibilityIdentifier("mobile.password.visibility")
        }
    }
}

/// Keep the same native field when revealing a password. Replacing a SwiftUI
/// SecureField with TextField ends the credential form and can trigger Save Password.
private struct PasswordTextField: UIViewRepresentable {
    let title: String
    @Binding
    var text: String
    let revealed: Bool
    let showsPlaceholder: Bool
    let isFocused: Binding<Bool>?
    let onSubmit: (() -> Void)?
    @Environment(\.isEnabled)
    private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.textContentType = .password
        field.returnKeyType = .go
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.accessibilityLabel = title
        field.placeholder = showsPlaceholder ? title : nil
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .label
        field.isEnabled = isEnabled
        if field.isSecureTextEntry == revealed {
            let selection = field.selectedTextRange.map {
                (
                    field.offset(from: field.beginningOfDocument, to: $0.start),
                    field.offset(from: field.beginningOfDocument, to: $0.end)
                )
            }
            field.isSecureTextEntry = !revealed
            // UIKit otherwise treats the next edit after re-masking as a
            // replacement. Reinsert into the same responder to reset that state.
            if field.isFirstResponder {
                field.text = ""
                field.insertText(text)
            } else {
                field.text = text
            }
            if let selection,
               let start = field.position(from: field.beginningOfDocument, offset: selection.0),
               let end = field.position(from: field.beginningOfDocument, offset: selection.1)
            {
                field.selectedTextRange = field.textRange(from: start, to: end)
            }
        }
        if field.text != text { field.text = text }
        if let isFocused {
            if isFocused.wrappedValue, !field.isFirstResponder {
                DispatchQueue.main.async {
                    guard context.coordinator.parent.isFocused?.wrappedValue == true,
                          field.window != nil, field.isEnabled else { return }
                    field.becomeFirstResponder()
                }
            } else if !isFocused.wrappedValue, field.isFirstResponder {
                field.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: max(44, (uiView.font?.lineHeight ?? 20) + 12))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PasswordTextField
        init(parent: PasswordTextField) {
            self.parent = parent
        }

        @objc
        func changed(_ field: UITextField) {
            let value = field.text ?? ""
            if parent.text != value { parent.text = value }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused?.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused?.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit?()
            return false
        }
    }
}
