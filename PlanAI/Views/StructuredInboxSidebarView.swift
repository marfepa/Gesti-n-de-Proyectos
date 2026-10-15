import SwiftUI
import SwiftData

public struct StructuredInboxSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    public let viewModel: ProjectViewModel
    public var onNewInboxTask: () -> Void = {}

    public init(viewModel: ProjectViewModel, onNewInboxTask: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onNewInboxTask = onNewInboxTask
    }

    /// Tareas alojadas en el Inbox ("Your Unstructured Thoughts") pendientes de agendar
    private var inboxTasks: [(project: Project, task: ProjectTask)] {
        var list: [(Project, ProjectTask)] = []
        for p in projects {
            for t in p.tasks where t.isInbox && !t.isCompleted {
                list.append((p, t))
            }
        }
        return list
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Cabecera: Píldora "Inbox" + Menú de navegación a Gantt / Proyectos
            HStack {
                Button {
                    viewModel.activeTab = .todayTimeline
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(String(localized: "Inbox"))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(StructuredTheme.coral)
                    .clipShape(Capsule())
                    .shadow(color: StructuredTheme.coral.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button(action: { viewModel.activeTab = .todayTimeline }) {
                        Label(String(localized: "Timeline Structured (Mi Día)"), systemImage: "sun.max.fill")
                    }
                    Button(action: { viewModel.activeTab = .weeklySchedule }) {
                        Label(String(localized: "Planificador de Capacidad Semanal"), systemImage: "calendar")
                    }
                    Divider()
                    ForEach(projects) { project in
                        Button(action: {
                            viewModel.selectedProject = project
                            viewModel.activeTab = .projects
                        }) {
                            Label(project.name, systemImage: "chart.bar.xaxis")
                        }
                    }
                    Divider()
                    Button(action: { viewModel.showingNewProjectSheet = true }) {
                        Label(String(localized: "Nuevo Proyecto con IA"), systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // 2. Contenido central: Ilustración vacía (Vídeo 00:01) o Lista de tareas arrastrables
            if inboxTasks.isEmpty {
                Spacer()
                emptyStateIllustration
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(inboxTasks, id: \.task.id) { item in
                            inboxTaskRow(task: item.task)
                                .draggable(item.task.id.uuidString)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                Button(action: onNewInboxTask) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text(String(localized: "New Inbox Task"))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(StructuredTheme.coral)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(StructuredTheme.coralLight)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 12)
            }

            // 3. Acceso directo a Proyectos con Gantt en el pie
            if !projects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .padding(.horizontal, 16)

                    HStack {
                        Text(String(localized: "Proyectos (Gantt & IA)"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(projects.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                    ForEach(projects.prefix(3)) { p in
                        Button {
                            viewModel.selectedProject = p
                            viewModel.activeTab = .projects
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(StructuredTheme.coral)
                                    .frame(width: 6, height: 6)
                                Text(p.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(p.progress * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private var emptyStateIllustration: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(StructuredTheme.coral.opacity(0.18))
                    .frame(width: 90, height: 74)

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(StructuredTheme.coral)
                        .frame(width: 70, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .frame(width: 32, height: 16)
                                .offset(y: -18)
                        )
                }
            }

            Text(String(localized: "Your Unstructured Thoughts"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(String(localized: "Capture tasks and thoughts as they come. Move them to your timeline when you're ready to schedule."))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .lineSpacing(2)

            Button(action: onNewInboxTask) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text(String(localized: "New Inbox Task"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(StructuredTheme.coral)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(StructuredTheme.coralLight)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(StructuredTheme.coral.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func inboxTaskRow(task: ProjectTask) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(StructuredTheme.coralLight)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: task.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StructuredTheme.coral)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(Int(round(task.estimatedHours * 60))) min")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                scheduleInboxTaskToToday(task)
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(StructuredTheme.coral)
            }
            .buttonStyle(.plain)
            .help("Mover al Timeline de hoy")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func scheduleInboxTaskToToday(_ task: ProjectTask) {
        task.isInbox = false
        task.hasFixedTime = true
        task.scheduledDate = Calendar.current.startOfDay(for: Date())
        task.fixedStartMinute = 600 // 10:00 AM
        task.fixedEndMinute = 600 + max(15, Int(round(task.estimatedHours * 60)))
        try? modelContext.save()
    }
}

