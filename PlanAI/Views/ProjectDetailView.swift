import SwiftUI
import SwiftData

public enum DetailTabMode: String, CaseIterable, Identifiable {
    case gantt
    case list
    case split

    public var id: String { rawValue }

    public var localizedLabel: String {
        switch self {
        case .gantt: return String(localized: "Gantt")
        case .list: return String(localized: "Lista")
        case .split: return String(localized: "Ambos")
        }
    }

    public var iconName: String {
        switch self {
        case .gantt: return "chart.bar.xaxis"
        case .list: return "list.bullet"
        case .split: return "square.split.2x1"
        }
    }
}

public struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable public var project: Project
    public let viewModel: ProjectViewModel

    @State private var selectedTab: DetailTabMode = .split
    @State private var selectedTask: ProjectTask?

    public init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Cabecera del Proyecto
            projectHeader
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Contenido según el modo seleccionado
            Group {
                switch selectedTab {
                case .gantt:
                    GanttChartView(
                        tasks: project.sortedTasks,
                        selectedTask: $selectedTask,
                        onEditTask: { task in
                            viewModel.editingTask = task
                            viewModel.showingTaskSheet = true
                        }
                    )
                    .padding()

                case .list:
                    TaskListView(
                        tasks: project.sortedTasks,
                        onToggle: { task in
                            viewModel.toggleTaskCompletion(task, context: modelContext)
                        },
                        onEdit: { task in
                            viewModel.editingTask = task
                            viewModel.showingTaskSheet = true
                        },
                        onDelete: { task in
                            viewModel.deleteTask(task, context: modelContext)
                        },
                        onToggleSubtask: { subtask in
                            viewModel.toggleSubtaskCompletion(subtask, context: modelContext)
                        },
                        onDecomposeTask: { task in
                            viewModel.decomposeTask(task, context: modelContext)
                        },
                        onAddSubtask: { task, title, hours in
                            viewModel.addSubtask(title: title, hours: hours, to: task, context: modelContext)
                        },
                        onDeleteSubtask: { subtask in
                            viewModel.deleteSubtask(subtask, context: modelContext)
                        }
                    )

                case .split:
                    VSplitView {
                        GanttChartView(
                            tasks: project.sortedTasks,
                            selectedTask: $selectedTask,
                            onEditTask: { task in
                                viewModel.editingTask = task
                                viewModel.showingTaskSheet = true
                            }
                        )
                        .frame(minHeight: 220)
                        .padding(.horizontal)
                        .padding(.top)

                        TaskListView(
                            tasks: project.sortedTasks,
                            onToggle: { task in
                                viewModel.toggleTaskCompletion(task, context: modelContext)
                            },
                            onEdit: { task in
                                viewModel.editingTask = task
                                viewModel.showingTaskSheet = true
                            },
                            onDelete: { task in
                                viewModel.deleteTask(task, context: modelContext)
                            },
                            onToggleSubtask: { subtask in
                                viewModel.toggleSubtaskCompletion(subtask, context: modelContext)
                            },
                            onDecomposeTask: { task in
                                viewModel.decomposeTask(task, context: modelContext)
                            },
                            onAddSubtask: { task, title, hours in
                                viewModel.addSubtask(title: title, hours: hours, to: task, context: modelContext)
                            },
                            onDeleteSubtask: { subtask in
                                viewModel.deleteSubtask(subtask, context: modelContext)
                            }
                        )
                        .frame(minHeight: 180)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTabMode.allCases) { mode in
                        Label(mode.localizedLabel, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button(action: {
                        viewModel.projectToEdit = project
                        viewModel.showingEditProjectSheet = true
                    }) {
                        Label(String(localized: "Editar Proyecto"), systemImage: "pencil")
                    }
                    .help(String(localized: "Editar nombre, fechas, prioridad y descripción"))

                    Button(action: {
                        viewModel.editingTask = nil
                        viewModel.showingTaskSheet = true
                    }) {
                        Label(String(localized: "Añadir Tarea"), systemImage: "plus")
                    }
                    .help(String(localized: "Añadir una tarea manual a este proyecto"))
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingEditProjectSheet },
            set: { viewModel.showingEditProjectSheet = $0 }
        )) {
            ProjectEditSheet(project: project, viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingTaskSheet },
            set: { viewModel.showingTaskSheet = $0 }
        )) {
            TaskEditSheet(
                task: viewModel.editingTask,
                onSave: { title, notes, start, end, hours in
                    viewModel.saveTask(
                        title: title,
                        notes: notes,
                        startDate: start,
                        endDate: end,
                        estimatedHours: hours,
                        in: project,
                        context: modelContext
                    )
                }
            )
        }
    }

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    if !project.projectDescription.isEmpty {
                        Text(project.projectDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Indicadores de resumen
                HStack(spacing: 20) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "Prioridad"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $project.priority) {
                            ForEach(ProjectPriority.allCases) { p in
                                Label(p.title, systemImage: p.iconName).tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 110)
                        .onChange(of: project.priority) { _, _ in
                            try? modelContext.save()
                        }
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "Duración"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(project.totalDurationInDays) " + String(localized: "días"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "Progreso"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(project.progress * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(project.progress == 1.0 ? .green : .blue)
                    }
                }
            }

            // Información de fechas y ajuste de ventana
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text(String(localized: "Inicio:"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(project.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .fontWeight(.medium)
                }

                HStack(spacing: 4) {
                    Text(String(localized: "Fin estimado:"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(project.estimatedEndDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .fontWeight(.medium)
                }

                if let target = project.targetEndDate {
                    HStack(spacing: 4) {
                        Text(String(localized: "Objetivo:"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(target.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(project.isOverdueOrExceedsTarget ? .orange : .green)
                    }

                    if project.isOverdueOrExceedsTarget {
                        Label {
                            Text("Excede \(project.targetVarianceInDays)d")
                                .font(.caption2)
                                .fontWeight(.bold)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.orange)
                    } else {
                        Label(String(localized: "En plazo"), systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }

            // Barra de progreso visual
            ProgressView(value: project.progress)
                .tint(project.progress == 1.0 ? .green : .blue)
        }
    }
}
