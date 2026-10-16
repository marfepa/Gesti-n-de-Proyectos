import SwiftUI
import SwiftData

public struct StructuredInboxSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \WorkSlot.sortOrder) private var workSlots: [WorkSlot]

    @AppStorage("structuredAccentTheme") private var accentColorToken: String = "coral"
    @AppStorage("structuredWakeUpMinute") private var wakeUpMinute: Int = 375
    @AppStorage("structuredWindDownMinute") private var windDownMinute: Int = 1305

    public let viewModel: ProjectViewModel
    public var onNewInboxTask: () -> Void = {}

    private let schedulerService = WeeklySchedulerService()

    public init(viewModel: ProjectViewModel, onNewInboxTask: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onNewInboxTask = onNewInboxTask
    }

    private var accentColor: Color {
        StructuredTheme.color(forToken: accentColorToken)
    }

    private var accentLightColor: Color {
        StructuredTheme.lightColor(forToken: accentColorToken)
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
            // 1. Selector de Navegación Principal (Hoy | Semana | Bandeja | Proyectos)
            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(ProjectViewModel.SidebarTab.allCases) { tab in
                        let isSelected = viewModel.activeTab == tab
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.activeTab = tab
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 12, weight: .bold))
                                Text(tab.title)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? .white : .primary.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? accentColor : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 16)

            // 2. Contenido central: Ilustración vacía o Lista de tareas arrastrables del Inbox
            if inboxTasks.isEmpty {
                Spacer()
                emptyStateIllustration
                Spacer()
            } else {
                HStack {
                    Label(String(localized: "Inbox Rápido (Arrastrable)"), systemImage: "tray.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(inboxTasks.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentLightColor)
                        .foregroundStyle(accentColor)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(inboxTasks, id: \.task.id) { item in
                            inboxTaskRow(task: item.task)
                                .draggable(item.task.id.uuidString)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }

                Button(action: onNewInboxTask) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text(String(localized: "New Inbox Task"))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(accentLightColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 10)
            }

            // 3. Acceso directo a todos los Proyectos con Gantt e identidad de color
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .padding(.horizontal, 16)

                HStack {
                    Text(String(localized: "Proyectos (Gantt & IA)"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.showingNewProjectSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                            Text(String(localized: "Nuevo"))
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)

                if projects.isEmpty {
                    Text(String(localized: "Sin proyectos creados aún."))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(projects) { p in
                                let isSelected = viewModel.activeTab == .projects && viewModel.selectedProject?.id == p.id
                                let pColor = StructuredTheme.color(forToken: p.colorToken)
                                Button {
                                    viewModel.selectedProject = p
                                    viewModel.activeTab = .projects
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: p.iconName)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(pColor)
                                            .frame(width: 20, height: 20)
                                            .background(StructuredTheme.lightColor(forToken: p.colorToken))
                                            .clipShape(RoundedRectangle(cornerRadius: 5))

                                        Text(p.name)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(Int(p.progress * 100))%")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(p.progress >= 1.0 ? StructuredTheme.mint : .secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? pColor.opacity(0.12) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        viewModel.projectToEdit = p
                                        viewModel.showingEditProjectSheet = true
                                    } label: {
                                        Label(String(localized: "Editar Proyecto"), systemImage: "pencil")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        viewModel.deleteProject(p, context: modelContext)
                                    } label: {
                                        Label(String(localized: "Eliminar Proyecto"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(maxHeight: 140)
                }
            }
            .padding(.bottom, 10)
        }
        .frame(minWidth: 265, idealWidth: 300, maxWidth: 340)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private var emptyStateIllustration: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 90, height: 74)

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor)
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
                .foregroundStyle(accentColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(accentLightColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(accentColor.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func inboxTaskRow(task: ProjectTask) -> some View {
        let taskColor = StructuredTheme.color(forToken: task.effectiveColorToken)
        let taskLight = StructuredTheme.lightColor(forToken: task.effectiveColorToken)

        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(taskLight)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: task.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(taskColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(Int(round(task.effectiveEstimatedHours * 60))) min")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                scheduleInboxTaskToToday(task)
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(taskColor)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Agendar en el próximo hueco libre de hoy"))
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button {
                scheduleInboxTaskToToday(task)
            } label: {
                Label(String(localized: "Mover al Timeline de Hoy"), systemImage: "calendar.badge.plus")
            }
            Button(role: .destructive) {
                viewModel.deleteTask(task, context: modelContext)
            } label: {
                Label(String(localized: "Eliminar"), systemImage: "trash")
            }
        }
    }

    private func scheduleInboxTaskToToday(_ task: ProjectTask) {
        let today = Calendar.current.startOfDay(for: Date())
        let currentSchedule = schedulerService.schedule(
            projects: projects,
            slots: workSlots,
            startDate: DayStripView.mondayOfWeek(containing: today),
            weeksToSchedule: 2
        )
        let durationMins = max(15, Int(round(task.effectiveEstimatedHours * 60)))
        let bestStart = schedulerService.findNextAvailableGap(
            on: today,
            durationMinutes: durationMins,
            existingItems: currentSchedule.scheduledItems,
            wakeUpMinute: wakeUpMinute,
            windDownMinute: windDownMinute
        )

        task.isInbox = false
        task.hasFixedTime = true
        task.scheduledDate = today
        task.fixedStartMinute = bestStart
        task.fixedEndMinute = min(1425, bestStart + durationMins)
        try? modelContext.save()
        Task { await NotificationService.shared.scheduleNotification(for: task) }
    }
}
