import SwiftUI
import SwiftData

/// Vista compacta para la barra de menús de macOS (`MenuBarExtra`) estilo Structured Focus HUD.
public struct MenuBarCompanionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \WorkSlot.sortOrder) private var workSlots: [WorkSlot]

    @AppStorage("structuredAccentTheme") private var accentColorToken: String = "coral"
    @AppStorage("structuredSafetyBuffer") private var safetyBufferPercent: Double = 0.15

    @State private var quickInboxText: String = ""
    @State private var currentTime: Date = Date()

    private let schedulerService = WeeklySchedulerService()
    private var calendar: Calendar { Calendar.current }

    public init() {}

    private var accentColor: Color {
        StructuredTheme.color(forToken: accentColorToken)
    }

    private var currentMinuteOfDay: Int {
        calendar.component(.hour, from: currentTime) * 60 + calendar.component(.minute, from: currentTime)
    }

    private var todayItems: [ScheduledItem] {
        let today = calendar.startOfDay(for: Date())
        let res = schedulerService.schedule(
            projects: projects,
            slots: workSlots,
            startDate: DayStripView.mondayOfWeek(containing: today),
            weeksToSchedule: 2,
            safetyBufferPercent: safetyBufferPercent
        )
        return res.scheduledItems
            .filter { calendar.isDate($0.date, inSameDayAs: today) && !$0.isCompleted }
            .sorted { $0.startMinute < $1.startMinute }
    }

    private var activeOrNextItem: ScheduledItem? {
        if let active = todayItems.first(where: { currentMinuteOfDay >= $0.startMinute && currentMinuteOfDay < $0.endMinute }) {
            return active
        }
        return todayItems.first(where: { $0.startMinute >= currentMinuteOfDay }) ?? todayItems.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cabecera
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(accentColor)
                Text(String(localized: "PlanAI · Mi Día"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(currentTime, style: .time)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Tarea en foco o próxima
            if let item = activeOrNextItem {
                let isLive = currentMinuteOfDay >= item.startMinute && currentMinuteOfDay < item.endMinute
                let itemColor = StructuredTheme.color(forToken: item.colorToken)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(itemColor)
                                .frame(width: 30, height: 30)
                            Image(systemName: item.iconName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(isLive ? String(localized: "EN CURSO") : String(localized: "PRÓXIMA"))
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .foregroundStyle(itemColor)
                                Text("· \(item.timeRangeFormatted)")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.displayTitle)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(2)
                        }

                        Spacer()
                    }

                    if isLive {
                        let totalMins = max(1, item.endMinute - item.startMinute)
                        let elapsed = max(0, currentMinuteOfDay - item.startMinute)
                        let rem = max(0, item.endMinute - currentMinuteOfDay)
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(elapsed), total: Double(totalMins))
                                .tint(itemColor)
                            Text(String(localized: "Quedan \(rem) min para finalizar este bloque"))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        completeItem(item)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(String(localized: "Completar Tarea Ahora"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(StructuredTheme.mint)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(StructuredTheme.mint)
                    Text(String(localized: "Todo despejado por hoy."))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Divider()

            // Captura rápida al Inbox desde cualquier lugar en macOS
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Captura Rápida al Inbox"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    TextField(String(localized: "Idea o tarea rápida..."), text: $quickInboxText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .rounded))
                        .onSubmit {
                            quickAddInbox()
                        }

                    Button {
                        quickAddInbox()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(quickInboxText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            currentTime = Date()
        }
    }

    private func completeItem(_ item: ScheduledItem) {
        for project in projects {
            for task in project.tasks {
                if let subId = item.subtaskId, let sub = task.subtasks.first(where: { $0.id == subId }) {
                    sub.isCompleted = true
                    if task.subtasks.allSatisfy(\.isCompleted) {
                        task.isCompleted = true
                    }
                    try? modelContext.save()
                    return
                } else if task.id == item.taskId {
                    task.isCompleted = true
                    for s in task.subtasks { s.isCompleted = true }
                    NotificationService.shared.cancelNotification(for: task.id)
                    try? modelContext.save()
                    return
                }
            }
        }
    }

    private func quickAddInbox() {
        let clean = quickInboxText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let targetProject: Project
        if let first = projects.first {
            targetProject = first
        } else {
            let created = Project(name: "Inbox & Mi Día", projectDescription: "Tareas rápidas")
            modelContext.insert(created)
            targetProject = created
        }

        let today = calendar.startOfDay(for: Date())
        let task = ProjectTask(
            title: clean,
            startDate: today,
            endDate: today,
            estimatedHours: 0.5,
            sortOrder: targetProject.tasks.count,
            isInbox: true,
            hasFixedTime: false,
            iconName: TaskDecompositionService.inferIcon(for: clean),
            colorToken: TaskDecompositionService.inferColor(for: clean),
            project: targetProject
        )
        modelContext.insert(task)
        targetProject.tasks.append(task)
        try? modelContext.save()
        quickInboxText = ""
    }
}
