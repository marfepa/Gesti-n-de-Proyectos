import SwiftUI
import SwiftData

/// Popover de detalle interactivo al pulsar un item en la rejilla semanal.
public struct ScheduledItemDetailPopover: View {
    public let item: ScheduledItem
    public let subtaskNotes: String?
    public let taskNotes: String?
    public var onToggle: () -> Void = {}
    public var onEdit: () -> Void = {}

    public init(
        item: ScheduledItem,
        subtaskNotes: String? = nil,
        taskNotes: String? = nil,
        onToggle: @escaping () -> Void = {},
        onEdit: @escaping () -> Void = {}
    ) {
        self.item = item
        self.subtaskNotes = subtaskNotes
        self.taskNotes = taskNotes
        self.onToggle = onToggle
        self.onEdit = onEdit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cabecera con Proyecto y Prioridad
            HStack(spacing: 8) {
                Circle()
                    .fill(priorityColor(item.projectPriority))
                    .frame(width: 10, height: 10)

                Text(item.projectName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(item.projectPriority.title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor(item.projectPriority).opacity(0.15))
                    .foregroundStyle(priorityColor(item.projectPriority))
                    .clipShape(Capsule())
            }

            Divider()

            // Título de Tarea y Subtarea
            VStack(alignment: .leading, spacing: 4) {
                Text(item.taskTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let sub = item.subtaskTitle, !sub.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(sub)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Horario y Duración
            HStack(spacing: 16) {
                Label(item.timeRangeFormatted, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(String(format: "%.1f horas asignadas", item.allocatedHours), systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Notas / Descripción detallada
            let effectiveNotes = (subtaskNotes?.isEmpty == false ? subtaskNotes : taskNotes) ?? ""
            if !effectiveNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Detalles:"))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(effectiveNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider()

            // Acciones: Toggle Completado y Editar Tarea
            HStack {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isCompleted ? .green : .secondary)
                        Text(item.isCompleted ? String(localized: "Completada") : String(localized: "Marcar Completada"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text(String(localized: "Editar Tarea"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func priorityColor(_ priority: ProjectPriority) -> Color {
        switch priority {
        case .baja: return .gray
        case .media: return .blue
        case .alta: return .orange
        case .urgente: return .red
        }
    }
}
