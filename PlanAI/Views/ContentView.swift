import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var viewModel = ProjectViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List {
                    Section {
                        Button {
                            viewModel.activeTab = .weeklySchedule
                        } label: {
                            HStack {
                                Label(String(localized: "Planificador Semanal"), systemImage: "calendar.badge.clock")
                                    .foregroundStyle(viewModel.activeTab == .weeklySchedule ? .blue : .primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }

                    Section(header: Text(String(localized: "Proyectos"))) {
                        ForEach(projects) { project in
                            Button {
                                viewModel.selectedProject = project
                                viewModel.activeTab = .projects
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(project.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(viewModel.activeTab == .projects && viewModel.selectedProject?.id == project.id ? .blue : .primary)

                                        HStack(spacing: 8) {
                                            HStack(spacing: 3) {
                                                Image(systemName: project.priority.iconName)
                                                Text(project.priority.title)
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(priorityColor(project.priority))

                                            Text("•")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Text("\(project.tasks.count) " + String(localized: "tareas"))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Text("•")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Text("\(Int(project.progress * 100))%")
                                                .font(.caption2)
                                                .foregroundStyle(project.progress == 1.0 ? .green : .blue)
                                        }
                                    }

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive, action: {
                                    viewModel.deleteProject(project, context: modelContext)
                                }) {
                                    Label(String(localized: "Eliminar Proyecto"), systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: deleteProjects)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Pie de barra lateral con estado de Apple Intelligence
                AIStatusBanner(service: viewModel.aiAvailability)
                    .padding(8)
            }
            .navigationTitle(String(localized: "PlanAI"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        viewModel.showingNewProjectSheet = true
                    }) {
                        Label(String(localized: "Nuevo Proyecto"), systemImage: "plus")
                    }
                    .help(String(localized: "Crear un nuevo proyecto con IA o manual"))
                }
            }
        } detail: {
            if viewModel.activeTab == .weeklySchedule {
                WeeklyScheduleView()
            } else if let selected = viewModel.selectedProject {
                ProjectDetailView(project: selected, viewModel: viewModel)
            } else {
                ContentUnavailableView(
                    String(localized: "Ningún proyecto seleccionado"),
                    systemImage: "folder.badge.gearshape",
                    description: Text(String(localized: "Selecciona un proyecto existente en la barra lateral o crea uno nuevo usando Apple Intelligence."))
                )
            }
        }
        .sheet(isPresented: $viewModel.showingNewProjectSheet) {
            ProjectInputView(viewModel: viewModel)
        }
        .onAppear {
            // Selecciona automáticamente el primer proyecto si existe y ninguno está seleccionado
            if viewModel.selectedProject == nil, let first = projects.first {
                viewModel.selectedProject = first
            }
        }
    }

    private func deleteProjects(offsets: IndexSet) {
        for index in offsets {
            let project = projects[index]
            viewModel.deleteProject(project, context: modelContext)
        }
    }

    private func priorityColor(_ priority: ProjectPriority) -> Color {
        switch priority {
        case .baja: return .secondary
        case .media: return .blue
        case .alta: return .orange
        case .urgente: return .red
        }
    }
}
