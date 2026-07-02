import SwiftUI
import Foundation

struct AddIconButton: View {
    let helpText: LocalizedStringResource
    var size: CGFloat = 18
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: size))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isDisabled ? .tertiary : .secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: helpText))
        .accessibilityLabel(String(localized: helpText))
        .disabled(isDisabled)
    }
}
