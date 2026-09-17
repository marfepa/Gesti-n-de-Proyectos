import SwiftUI
import SwiftData

public struct TaskListView: View {
    public let tasks: [ProjectTask]
    public let onToggle: (ProjectTask) -> Void
    public let onEdit: (ProjectTask) -> Void
    public let onDelete: (ProjectTask) -> Void
    public let onToggleSubtask: (ProjectSubtask) -> Void
    public let onDecomposeTask: (ProjectTask) -> Void
    public let onAddSubtask: (ProjectTask, String, Double) -> Void
    public let onDeleteSubtask: (ProjectSubtask) -> Void

    @State private var expandedTaskIds: Set<UUID> = []
    @State private var addingSubtaskToId: UUID?
    @State private var newSubtaskTitle: String = ""
    @State private var newSubtaskHours: Double = 1.0

    public init(
        tasks: [ProjectTask],
        onToggle: @escaping (ProjectTask) -> Void,
        onEdit: @escaping (ProjectTask) -> Void,
        onDelete: @escaping (ProjectTask) -> Void,
        onToggleSubtask: @escaping (ProjectSubtask) -> Void = { _ in },
        onDecomposeTask: @escaping (ProjectTask) -> Void = { _ in },
        onAddSubtask: @escaping (ProjectTask, String, Double) -> Void = { _, _, _ in },
        onDeleteSubtask: @escaping (ProjectSubtask) -> Void = { _ in }
    ) {
        self.tasks = tasks
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onToggleSubtask = onToggleSubtask
        self.onDecomposeTask = onDecomposeTask
        self.onAddSubtask = onAddSubtask
        self.onDeleteSubtask = onDeleteSubtask
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
                    VStack(alignment: .leading, spacing: 6) {
                        // Fila de tarea principal
                        HStack(alignment: .top, spacing: 10) {
                            // Botón de expansión para tareas con subtareas o grandes
                            Button(action: {
                                toggleExpand(task.id)
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(task.subtasks.isEmpty ? Color.clear : Color.secondary)
                                    .rotationEffect(expandedTaskIds.contains(task.id) ? .degrees(90) : .degrees(0))
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(task.subtasks.isEmpty && !task.isLargeTask)
                            .padding(.top, 4)

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

                                    if task.isLargeTask {
                                        Text("Fase Extensa")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.12))
                                            .foregroundStyle(.purple)
                                            .clipShape(Capsule())
                                    }

                                    Spacer()

                                    Text(task.dateRangeFormatted)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(String(format: "%.1fh", task.effectiveEstimatedHours))
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

                                // Indicador de progreso de subtareas si existen
                                if !task.subtasks.isEmpty {
                                    HStack(spacing: 6) {
                                        ProgressView(value: task.subtasksProgress)
                                            .progressViewStyle(.linear)
                                            .frame(maxWidth: 100)
                                            .tint(task.isCompleted ? .green : .blue)

                                        let completedCount = task.subtasks.filter(\.isCompleted).count
                                        Text("\(completedCount)/\(task.subtasks.count) subtareas")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 2)
                                }
                            }

                            HStack(spacing: 6) {
                                if task.subtasks.isEmpty {
                                    Button(action: {
                                        onDecomposeTask(task)
                                        expandedTaskIds.insert(task.id)
                                    }) {
                                        Label("Desglosar", systemImage: "arrow.triangle.branch")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help(String(localized: "Desglosar en subtareas accionables"))
                                }

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

                        // Sección desplegada de subtareas
                        if expandedTaskIds.contains(task.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(task.sortedSubtasks) { subtask in
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        Button(action: {
                                            onToggleSubtask(subtask)
                                        }) {
                                            Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                                .font(.caption)
                                                .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                                        }
                                        .buttonStyle(.plain)

                                        Text(subtask.title)
                                            .font(.caption)
                                            .strikethrough(subtask.isCompleted, color: .secondary)
                                            .foregroundStyle(subtask.isCompleted ? .secondary : .primary)

                                        Spacer()

                                        Text(String(format: "%.1fh", subtask.estimatedHours))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)

                                        Button(role: .destructive, action: {
                                            onDeleteSubtask(subtask)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.leading, 28)
                                    .padding(.vertical, 2)
                                }

                                // Botón o formulario en línea para añadir subtarea
                                if addingSubtaskToId == task.id {
                                    HStack(spacing: 6) {
                                        TextField(String(localized: "Nombre de subtarea"), text: $newSubtaskTitle)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.small)

                                        Picker("", selection: $newSubtaskHours) {
                                            Text("0.5h").tag(0.5)
                                            Text("1.0h").tag(1.0)
                                            Text("2.0h").tag(2.0)
                                            Text("3.0h").tag(3.0)
                                            Text("4.0h").tag(4.0)
                                        }
                                        .pickerStyle(.menu)
                                        .frame(width: 70)
                                        .controlSize(.small)

                                        Button(String(localized: "Añadir")) {
                                            onAddSubtask(task, newSubtaskTitle, newSubtaskHours)
                                            newSubtaskTitle = ""
                                            addingSubtaskToId = nil
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                        Button(String(localized: "Cancelar")) {
                                            addingSubtaskToId = nil
                                            newSubtaskTitle = ""
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(.leading, 28)
                                    .padding(.top, 4)
                                } else {
                                    Button(action: {
                                        addingSubtaskToId = task.id
                                        newSubtaskTitle = ""
                                        newSubtaskHours = 1.0
                                    }) {
                                        Label(String(localized: "Añadir subtarea"), systemImage: "plus")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.blue)
                                    .padding(.leading, 28)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
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
                        Button(action: {
                            onDecomposeTask(task)
                            expandedTaskIds.insert(task.id)
                        }) {
                            Label(String(localized: "Desglosar en subtareas"), systemImage: "arrow.triangle.branch")
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

    private func toggleExpand(_ id: UUID) {
        if expandedTaskIds.contains(id) {
            expandedTaskIds.remove(id)
        } else {
            expandedTaskIds.insert(id)
        }
    }
}
