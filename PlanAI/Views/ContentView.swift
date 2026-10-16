import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var viewModel = ProjectViewModel()
    @State private var showingInboxTaskCreationSheet: Bool = false

    public init() {}

    public var body: some View {
        HSplitView {
            // Panel Izquierdo: Navegación + Inbox ("Your Unstructured Thoughts") con soporte de Drag & Drop
            StructuredInboxSidebarView(
                viewModel: viewModel,
                onNewInboxTask: {
                    showingInboxTaskCreationSheet = true
                }
            )

            // Panel Derecho: Timeline Principal, Planificador, Bandeja o Diagrama de Gantt
            Group {
                switch viewModel.activeTab {
                case .todayTimeline:
                    DailyTimelineContainerView(viewModel: viewModel)
                case .inbox:
                    UnscheduledInboxView(viewModel: viewModel)
                case .weeklySchedule:
                    WeeklyScheduleView()
                case .projects:
                    if let selected = viewModel.selectedProject {
                        ProjectDetailView(project: selected, viewModel: viewModel)
                    } else if let first = projects.first {
                        ProjectDetailView(project: first, viewModel: viewModel)
                    } else {
                        ContentUnavailableView(
                            String(localized: "Sin proyecto seleccionado"),
                            systemImage: "folder.badge.plus",
                            description: Text(String(localized: "Crea tu primer proyecto usando Apple Intelligence."))
                        )
                    }
                }
            }
            .frame(minWidth: 540)
        }
        .sheet(isPresented: $showingInboxTaskCreationSheet) {
            StructuredTaskCreationSheet(
                initialDate: Date(),
                initialStartMinute: 600,
                isInboxMode: true,
                projects: projects,
                onSave: { draft in
                    saveNewInboxTask(from: draft)
                },
                onClose: {
                    showingInboxTaskCreationSheet = false
                }
            )
        }
        .sheet(isPresented: $viewModel.showingNewProjectSheet) {
            ProjectInputView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingEditProjectSheet) {
            if let proj = viewModel.projectToEdit {
                ProjectEditSheet(project: proj, viewModel: viewModel)
            }
        }
        .onAppear {
            if viewModel.selectedProject == nil, let first = projects.first {
                viewModel.selectedProject = first
            }
        }
    }

    private func saveNewInboxTask(from draft: StructuredTaskDraft) {
        let targetProject: Project
        if let pid = draft.projectId, let found = projects.first(where: { $0.id == pid }) {
            targetProject = found
        } else if let first = projects.first {
            targetProject = first
        } else {
            let newProject = Project(
                name: "Inbox & Mi Día",
                projectDescription: "Tareas rápidas y pensamientos sin estructurar",
                priority: .media,
                colorToken: draft.colorToken
            )
            modelContext.insert(newProject)
            targetProject = newProject
        }

        let today = Calendar.current.startOfDay(for: Date())
        let hours = max(0.25, Double(draft.durationMinutes) / 60.0)

        let newTask = ProjectTask(
            title: draft.title,
            notes: draft.notes,
            startDate: today,
            endDate: today,
            estimatedHours: hours,
            sortOrder: targetProject.tasks.count,
            scheduledDate: nil,
            isInbox: true,
            hasFixedTime: false,
            iconName: draft.iconName,
            colorToken: draft.colorToken,
            alertOffsetMinutes: draft.alertOffsetMinutes,
            project: targetProject
        )
        modelContext.insert(newTask)
        targetProject.tasks.append(newTask)
        try? modelContext.save()
    }
}
