import SwiftUI
import AppKit

enum CustomModelRowAction: String, CaseIterable, Identifiable {
    case edit
    case delete

    static let visibleActions: [CustomModelRowAction] = [.edit, .delete]

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .edit:
            return "pencil"
        case .delete:
            return "trash"
        }
    }

    var helpText: LocalizedStringResource {
        switch self {
        case .edit:
            return "Edit Model"
        case .delete:
            return "Delete Model"
        }
    }

    var isDestructive: Bool {
        self == .delete
    }
}

// MARK: - Custom Model Card View
struct CustomModelCardView: View {
    let model: CustomCloudModel
    var deleteAction: () -> Void
    var editAction: (CustomCloudModel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main card content
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                actionSection
            }
            .padding(16)
        }
        .background(AppMaterialCardBackground())
    }
    
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))
            
            Spacer()
        }
    }
    
    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label(model.modelName, systemImage: "cube")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            Label(model.requestMode.detailTitle, systemImage: "arrow.left.arrow.right")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // Language
            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
            
            // OpenAI Compatible
            Label("OpenAI Compatible", systemImage: "checkmark.seal")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
        }
        .lineLimit(1)
    }
    
    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    
    private var actionSection: some View {
        HStack(spacing: 8) {
            modelStatusPill("Configured", systemImage: "checkmark.circle")

            CustomModelRowActionButton(rowAction: .edit) {
                editAction(model)
            }

            CustomModelRowActionButton(rowAction: .delete) {
                deleteAction()
            }
        }
    }
}

struct CustomModelRowActionButton: View {
    let rowAction: CustomModelRowAction
    let action: () -> Void

    var body: some View {
        Button(role: rowAction.isDestructive ? .destructive : nil, action: action) {
            Image(systemName: rowAction.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(rowAction.isDestructive ? AppTheme.Status.error : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.Surface.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: rowAction.helpText))
        .accessibilityLabel(String(localized: rowAction.helpText))
    }
}
