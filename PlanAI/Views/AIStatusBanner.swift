import SwiftUI

public struct AIStatusBanner: View {
    public let service: AIAvailabilityService

    public init(service: AIAvailabilityService) {
        self.service = service
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: service.isChecking)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(service.localizedDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !service.status.isAvailable {
                Button(action: {
                    service.checkAvailability()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Volver a comprobar disponibilidad"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch service.status {
        case .ready:
            return "brain.head.profile"
        case .deviceNotEligible:
            return "exclamationmark.triangle.fill"
        case .appleIntelligenceNotEnabled:
            return "gearshape.badge.exclamationmark"
        case .modelDownloading:
            return "arrow.down.circle"
        default:
            return "info.circle"
        }
    }

    private var iconColor: Color {
        switch service.status {
        case .ready:
            return .purple
        case .deviceNotEligible:
            return .orange
        case .appleIntelligenceNotEnabled:
            return .yellow
        case .modelDownloading:
            return .blue
        default:
            return .secondary
        }
    }

    private var titleText: String {
        switch service.status {
        case .ready:
            return String(localized: "Apple Intelligence (On-Device ANE)")
        case .deviceNotEligible:
            return String(localized: "Dispositivo no compatible con IA local")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Apple Intelligence desactivado")
        case .modelDownloading:
            return String(localized: "Descargando modelo on-device")
        default:
            return String(localized: "Estado del motor IA")
        }
    }

    private var backgroundColor: Color {
        switch service.status {
        case .ready:
            return Color.purple.opacity(0.08)
        case .deviceNotEligible, .appleIntelligenceNotEnabled:
            return Color.orange.opacity(0.08)
        default:
            return Color.gray.opacity(0.08)
        }
    }

    private var borderColor: Color {
        switch service.status {
        case .ready:
            return Color.purple.opacity(0.2)
        case .deviceNotEligible, .appleIntelligenceNotEnabled:
            return Color.orange.opacity(0.2)
        default:
            return Color.gray.opacity(0.2)
        }
    }
}
