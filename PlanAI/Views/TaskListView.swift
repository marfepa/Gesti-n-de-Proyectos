import SwiftUI
import SwiftData

public struct TaskListView: View {
    public let tasks: [ProjectTask]
    public let onToggle: (ProjectTask) -> Void
    public let onEdit: (ProjectTask) -> Void
    public let onDelete: (ProjectTask) -> Void

    public init(
        tasks: [ProjectTask],
        onToggle: @escaping (ProjectTask) -> Void,
        onEdit: @escaping (ProjectTask) -> Void,
        onDelete: @escaping (ProjectTask) -> Void
    ) {
        self.tasks = tasks
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        if tasks.isEmpty {
            ContentUnavailableView(
                String(localized: "No hay tareas registradas"),
                systemImage: "checklist",
                description: Text(String(localized: "Agrega tareas con el botón superior o genera el plan con IA."))
            )
        } else {
            List {
                ForEach(tasks) { task in
                    HStack(alignment: .top, spacing: 12) {
                        Button(action: {
                            onToggle(task)
                        }) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(task.isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(task.title)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .strikethrough(task.isCompleted, color: .secondary)
                                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                                Spacer()

                                Text(task.dateRangeFormatted)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("\(task.durationInDays)d")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }

                            if !task.notes.isEmpty {
                                Text(task.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                onEdit(task)
                            }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Editar tarea"))

                            Button(role: .destructive, action: {
                                onDelete(task)
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Eliminar tarea"))
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(action: { onToggle(task) }) {
                            Label(
                                task.isCompleted ? String(localized: "Marcar como pendiente") : String(localized: "Marcar como completada"),
                                systemImage: task.isCompleted ? "circle" : "checkmark.circle"
                            )
                        }
                        Button(action: { onEdit(task) }) {
                            Label(String(localized: "Editar"), systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive, action: { onDelete(task) }) {
                            Label(String(localized: "Eliminar"), systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}
