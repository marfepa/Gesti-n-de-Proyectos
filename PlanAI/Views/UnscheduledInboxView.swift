import SwiftUI
import SwiftData

/// Vista de Bandeja de Entrada inspirada en el Inbox de Structured.
/// Muestra las tareas pendientes del backlog y de todos los proyectos que están
/// a la espera de ser ejecutadas o programadas, con filtros rápidos y acciones directas.
public struct UnscheduledInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    public let viewModel: ProjectViewModel

    @State private var filterProject: Project?
    @State private var searchText: String = ""

    public init(viewModel: ProjectViewModel) {
        self.viewModel = viewModel
    }

    /// Todas las tareas pendientes a través de los proyectos
    private var pendingTasks: [(project: Project, task: ProjectTask)] {
        var list: [(Project, ProjectTask)] = []
        for project in projects {
            if let filter = filterProject, filter.id != project.id {
                continue
            }
            for task in project.tasks where !task.isCompleted {
                if searchText.isEmpty ||
                    task.title.localizedCaseInsensitiveContains(searchText) ||
                    project.name.localizedCaseInsensitiveContains(searchText) {
                    list.append((project, task))
                }
            }
        }
        return list
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Cabecera del Inbox estilo Structured
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(StructuredTheme.ocean)

                        Text(String(localized: "Bandeja de Entrada"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }

                    Text("\(pendingTasks.count) tareas pendientes en total")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Filtro por proyecto
                if !projects.isEmpty {
                    Picker(String(localized: "Proyecto"), selection: $filterProject) {
                        Text(String(localized: "Todos los proyectos")).tag(Project?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(Project?.some(project))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                }

                // Buscador rápido
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Buscar tarea..."), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 160)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if pendingTasks.isEmpty {
                emptyInboxView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(pendingTasks, id: \.task.id) { pair in
                            inboxTaskCard(project: pair.project, task: pair.task)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
    }

    // MARK: - Tarjeta de Tarea en Bandeja
    @ViewBuilder
    private func inboxTaskCard(project: Project, task: ProjectTask) -> some View {
        let tint = StructuredTheme.color(for: project.priority)

        HStack(alignment: .top, spacing: 14) {
            // Checkbox para completar
            Button {
                viewModel.toggleTaskCompletion(task, context: modelContext)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(task.isCompleted ? StructuredTheme.mint : Color.gray.opacity(0.40))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // Contenido de la tarea
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)

                    Spacer()

                    Text(project.priority.title)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.12))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }

                Text(task.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Subtareas resumidas si las tiene
                if !task.subtasks.isEmpty {
                    let completedSub = task.subtasks.filter { $0.isCompleted }.count
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 10))
                        Text("\(completedSub) de \(task.subtasks.count) subtareas")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Botones de acción rápida
            HStack(spacing: 6) {
                Button {
                    viewModel.selectedProject = project
                    viewModel.activeTab = .projects
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Ver en el proyecto")

                Button {
                    viewModel.editingTask = task
                    viewModel.showingTaskSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Editar tarea")
            }
        }
        .padding(14)
        .structuredCard()
    }

    // MARK: - Estado Vacío
    private var emptyInboxView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(StructuredTheme.mint.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(StructuredTheme.mint)
            }

            VStack(spacing: 6) {
                Text(String(localized: "Bandeja Limpia"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(String(localized: "No hay tareas pendientes en la bandeja. Puedes crear un nuevo proyecto o añadir tareas para comenzar."))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button {
                viewModel.showingNewProjectSheet = true
            } label: {
                Label(String(localized: "Nuevo Proyecto con IA"), systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
