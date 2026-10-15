import SwiftUI
import SwiftData

public struct DailyTimelineContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \WorkSlot.sortOrder) private var workSlots: [WorkSlot]

    public var viewModel: ProjectViewModel?

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isSheetExpanded: Bool = true
    @State private var showingTaskCreationPopover: Bool = false
    @State private var taskCreationStartMinute: Int = 600
    @State private var showingSettingsModal: Bool = false
    @State private var showingAddSlotSheet: Bool = false
    @State private var showingAISheet: Bool = false

    private let schedulerService = WeeklySchedulerService()

    public init(viewModel: ProjectViewModel? = nil) {
        self.viewModel = viewModel
    }

    private var scheduleResult: ScheduleResult {
        schedulerService.schedule(
            projects: projects,
            slots: workSlots,
            startDate: DayStripView.mondayOfWeek(containing: selectedDate),
            weeksToSchedule: 8,
            safetyBufferPercent: 0.15
        )
    }

    private var itemsForSelectedDay: [ScheduledItem] {
        scheduleResult.scheduledItems.filter {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // 1. Cabecera superior y selector de los 7 días
                DayStripView(
                    selectedDate: $selectedDate,
                    isSheetExpanded: $isSheetExpanded,
                    scheduledItems: scheduleResult.scheduledItems,
                    onOpenAI: { showingAISheet = true },
                    onOpenSearch: {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            isSheetExpanded.toggle()
                        }
                    },
                    onOpenSettings: { showingSettingsModal = true }
                )

                // 2. Cuerpo: Tallos Semanales + Hoja Inferior
                if isSheetExpanded {
                    DailyTimelineView(
                        result: scheduleResult,
                        workSlots: workSlots,
                        selectedDate: $selectedDate,
                        isSheetExpanded: $isSheetExpanded,
                        onToggleItem: { item in
                            toggleItemCompletion(item)
                        },
                        onAddNewTask: { suggestedMinute in
                            taskCreationStartMinute = suggestedMinute ?? 600
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingTaskCreationPopover = true
                            }
                        },
                        onOpenAI: {
                            showingAISheet = true
                        },
                        onDropInboxTask: { droppedTaskId in
                            scheduleDroppedInboxTask(taskIdString: droppedTaskId)
                        }
                    )
                } else {
                    // En modo colapsado usamos un VStack limpio para que los tallos terminen
                    // exactamente encima del Bottom Sheet sin ocultar las lunas (Vídeo 00:01 y 00:35)
                    VStack(spacing: 6) {
                        StructuredWeeklyStemsView(
                            selectedDate: $selectedDate,
                            scheduledItems: scheduleResult.scheduledItems,
                            onSelectDay: { day in
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    selectedDate = day
                                    isSheetExpanded = true
                                }
                            }
                        )
                        .frame(maxHeight: .infinity)

                        DailyTimelineView(
                            result: scheduleResult,
                            workSlots: workSlots,
                            selectedDate: $selectedDate,
                            isSheetExpanded: $isSheetExpanded,
                            onToggleItem: { item in
                                toggleItemCompletion(item)
                            },
                            onAddNewTask: { suggestedMinute in
                                taskCreationStartMinute = suggestedMinute ?? 600
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showingTaskCreationPopover = true
                                }
                            },
                            onOpenAI: {
                                showingAISheet = true
                            },
                            onDropInboxTask: { droppedTaskId in
                                scheduleDroppedInboxTask(taskIdString: droppedTaskId)
                            }
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .background(StructuredTheme.canvasBackground(for: colorScheme))

            // POPOVER FLOTANTE DERECHO DE CREACIÓN DE TAREA
            if showingTaskCreationPopover {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingTaskCreationPopover = false
                        }
                    }

                StructuredTaskCreationSheet(
                    initialDate: selectedDate,
                    initialStartMinute: taskCreationStartMinute,
                    isInboxMode: false,
                    existingItemsForDay: itemsForSelectedDay,
                    onSave: { draft in
                        createNewTask(from: draft)
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingTaskCreationPopover = false
                        }
                    }
                )
                .padding(.top, 20)
                .padding(.trailing, 20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(10)
            }

            // MODAL CENTRADO DE SETTINGS
            if showingSettingsModal {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingSettingsModal = false
                    }

                StructuredSettingsModalView(
                    onManageWorkSlots: {
                        showingSettingsModal = false
                        showingAddSlotSheet = true
                    },
                    onOpenAIProjectCreator: {
                        showingSettingsModal = false
                        showingAISheet = true
                    },
                    onClose: {
                        showingSettingsModal = false
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .zIndex(20)
            }
        }
        .sheet(isPresented: $showingAddSlotSheet) {
            AddWorkSlotSheet { newSlots in
                for slot in newSlots {
                    modelContext.insert(slot)
                }
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showingAISheet) {
            ProjectInputView(viewModel: viewModel ?? ProjectViewModel())
        }
        .onAppear {
            if workSlots.isEmpty {
                for slot in WorkSlot.defaultSlots() {
                    modelContext.insert(slot)
                }
                try? modelContext.save()
            }
        }
    }

    private func createNewTask(from draft: StructuredTaskDraft) {
        let targetProject: Project
        if let first = projects.first {
            targetProject = first
        } else {
            let newProject = Project(
                name: "Structured Timeline",
                projectDescription: "Tareas diarias y proyectos",
                priority: .media
            )
            modelContext.insert(newProject)
            targetProject = newProject
        }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: draft.date)
        let taskStart = calendar.date(byAdding: .minute, value: draft.startMinute, to: dayStart) ?? dayStart
        let taskEnd = calendar.date(byAdding: .minute, value: draft.endMinute, to: dayStart) ?? dayStart
        let hours = max(0.05, Double(draft.durationMinutes) / 60.0)

        let newTask = ProjectTask(
            title: draft.title,
            notes: draft.notes,
            startDate: taskStart,
            endDate: taskEnd,
            estimatedHours: hours,
            sortOrder: targetProject.tasks.count,
            scheduledDate: dayStart,
            isInbox: draft.isInbox,
            hasFixedTime: !draft.isInbox,
            fixedStartMinute: draft.isInbox ? nil : draft.startMinute,
            fixedEndMinute: draft.isInbox ? nil : draft.endMinute,
            iconName: draft.iconName,
            project: targetProject
        )
        modelContext.insert(newTask)
        targetProject.tasks.append(newTask)

        for (idx, subTitle) in draft.subtasks.enumerated() {
            let sub = ProjectSubtask(
                title: subTitle,
                estimatedHours: max(0.25, hours / Double(max(1, draft.subtasks.count))),
                sortOrder: idx,
                task: newTask
            )
            modelContext.insert(sub)
            newTask.subtasks.append(sub)
        }

        try? modelContext.save()
    }

    private func scheduleDroppedInboxTask(taskIdString: String) {
        guard let uuid = UUID(uuidString: taskIdString) else { return }
        for project in projects {
            if let task = project.tasks.first(where: { $0.id == uuid }) {
                task.isInbox = false
                task.hasFixedTime = true
                task.scheduledDate = Calendar.current.startOfDay(for: selectedDate)
                task.fixedStartMinute = 600
                task.fixedEndMinute = 630
                try? modelContext.save()
                return
            }
        }
    }

    private func toggleItemCompletion(_ item: ScheduledItem) {
        for project in projects {
            for task in project.tasks {
                if let subId = item.subtaskId, let sub = task.subtasks.first(where: { $0.id == subId }) {
                    sub.isCompleted.toggle()
                    let allCompleted = task.subtasks.allSatisfy { $0.isCompleted }
                    if allCompleted && !task.subtasks.isEmpty {
                        task.isCompleted = true
                    } else if !sub.isCompleted {
                        task.isCompleted = false
                    }
                    try? modelContext.save()
                    return
                } else if task.id == item.taskId {
                    task.isCompleted.toggle()
                    if task.isCompleted {
                        for s in task.subtasks {
                            s.isCompleted = true
                        }
                    }
                    try? modelContext.save()
                    return
                }
            }
        }
    }
}

// MARK: - Vista Semanal de Tallos Verticales Calibrada (Vídeo 00:01 y 00:35)
public struct StructuredWeeklyStemsView: View {
    @Binding public var selectedDate: Date
    public let scheduledItems: [ScheduledItem]
    public var onSelectDay: (Date) -> Void

    private let startHour = 6   // 06:00
    private let endHour = 22    // 22:00
    private let topPad: CGFloat = 16
    private let bottomPad: CGFloat = 24
    private var calendar: Calendar { Calendar.current }

    private var daysInWeek: [Date] {
        let monday = DayStripView.mondayOfWeek(containing: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Calcula la posición Y exacta compartida tanto por la regla de horas como por las cápsulas
    private func yPosition(forMinute minute: Int, totalHeight: CGFloat) -> CGFloat {
        let trackHeight = max(180, totalHeight - topPad - bottomPad)
        let minMinute = CGFloat(startHour * 60)
        let maxMinute = CGFloat(endHour * 60)
        let clamped = max(minMinute, min(maxMinute, CGFloat(minute)))
        let ratio = (clamped - minMinute) / (maxMinute - minMinute)
        return topPad + ratio * trackHeight
    }

    public var body: some View {
        GeometryReader { geo in
            let totalHeight = max(240, geo.size.height - 6)

            HStack(alignment: .top, spacing: 0) {
                // 1. Regla de horas graduada a la izquierda (sin que los ticks pisen los números)
                ZStack(alignment: .topTrailing) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        let y = yPosition(forMinute: hour * 60, totalHeight: totalHeight)
                        HStack(spacing: 4) {
                            Text("\(hour):00")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.75))
                                .monospacedDigit()
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 5, height: 1)
                        }
                        .offset(y: y - 6)

                        // Marca intermedia de 30 min colocada exactamente a mitad de camino
                        if hour < endHour {
                            let halfY = yPosition(forMinute: hour * 60 + 30, totalHeight: totalHeight)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 4, height: 1)
                                .offset(y: halfY)
                        }
                    }
                }
                .frame(width: 48, height: totalHeight, alignment: .topTrailing)

                // 2. Las 7 Columnas de Tallos Semanales
                ForEach(daysInWeek, id: \.self) { date in
                    stemColumn(for: date, totalHeight: totalHeight)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private struct PositionedStemCapsule: Identifiable {
        let id: UUID
        let item: ScheduledItem
        let yOffset: CGFloat
        let height: CGFloat
    }

    /// Calcula las posiciones de las cápsulas evitando que dos tareas del mismo día se tapen entre sí
    private func computeStemCapsules(for date: Date, totalHeight: CGFloat) -> [PositionedStemCapsule] {
        let dayItems = scheduledItems
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.startMinute < $1.startMinute }

        let topLimit = yPosition(forMinute: startHour * 60, totalHeight: totalHeight) + 18
        let bottomLimit = yPosition(forMinute: endHour * 60, totalHeight: totalHeight) - 24

        var results: [PositionedStemCapsule] = []
        var lastBottomY: CGFloat = topLimit

        for item in dayItems {
            let startY = yPosition(forMinute: item.startMinute, totalHeight: totalHeight)
            let endY = yPosition(forMinute: item.endMinute, totalHeight: totalHeight)
            let rawHeight = max(28, min(64, endY - startY))

            // Si empieza encima de la cápsula anterior, la desplazamos justo debajo para que ambas se vean (Vídeo 00:35)
            let adjustedY = max(startY, lastBottomY + 2)
            let clampedY = min(adjustedY, bottomLimit - rawHeight)

            results.append(
                PositionedStemCapsule(
                    id: item.id,
                    item: item,
                    yOffset: clampedY,
                    height: rawHeight
                )
            )
            lastBottomY = clampedY + rawHeight
        }
        return results
    }

    @ViewBuilder
    private func stemColumn(for date: Date, totalHeight: CGFloat) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let startY = yPosition(forMinute: startHour * 60, totalHeight: totalHeight)
        let endY = yPosition(forMinute: endHour * 60, totalHeight: totalHeight)
        let capsules = computeStemCapsules(for: date, totalHeight: totalHeight)

        ZStack(alignment: .top) {
            // Tallo vertical central desde las 06:00 hasta las 22:00
            Rectangle()
                .fill(isSelected ? StructuredTheme.coral.opacity(0.65) : Color.secondary.opacity(0.25))
                .frame(width: 2.5, height: max(10, endY - startY))
                .offset(y: startY)

            // Icono superior de Despertar (06:00)
            Circle()
                .fill(StructuredTheme.coralLight)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(StructuredTheme.coral)
                )
                .offset(y: startY - 13)

            // Cápsulas de tareas (Alineadas con su hora real y sin taparse entre sí)
            ForEach(capsules) { cap in
                ZStack {
                    Capsule()
                        .fill(StructuredTheme.coral)
                        .frame(width: 28, height: cap.height)
                        .overlay(
                            Capsule().stroke(Color.white, lineWidth: 1.5)
                        )
                    Image(systemName: cap.item.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(y: cap.yOffset)
            }

            // Icono inferior de Dormir (Luna a las 22:00, siempre visible sobre el Bottom Sheet)
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 34, height: 48)
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .offset(y: -8)
                }
                Circle()
                    .fill(StructuredTheme.nightNavy.opacity(0.18))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "moon.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(StructuredTheme.nightNavy)
                    )
            }
            .offset(y: endY - 13)
        }
        .frame(height: totalHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectDay(date)
        }
    }
}

// MARK: - Modal de Settings
public struct StructuredSettingsModalView: View {
    public var onManageWorkSlots: () -> Void
    public var onOpenAIProjectCreator: () -> Void
    public var onClose: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Settings")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 24))
                                .foregroundStyle(StructuredTheme.coral)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PlanAI + Apple Intelligence")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Text("Plan your day better with on-device AI decomposition, voice dictation and Gantt charts.")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(action: onOpenAIProjectCreator) {
                            Text("Create Project with Apple Intelligence")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(StructuredTheme.coral)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(StructuredTheme.coralLight.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    settingsGroup(title: "General & Schedule", rows: [
                        ("bell.fill", StructuredTheme.coral, "Notifications & Alerts", "Set Up >", {}),
                        ("clock.fill", StructuredTheme.ocean, "Work Slots (Momentos Disponibles)", "Configure >", onManageWorkSlots),
                        ("paintbrush.fill", StructuredTheme.lavender, "Customization", "Coral >", {})
                    ])

                    settingsGroup(title: "Features", rows: [
                        ("sparkles", StructuredTheme.teal, "Replan with AI", "Active >", onOpenAIProjectCreator),
                        ("bolt.heart.fill", StructuredTheme.amber, "Energy Monitor (SafeLoad)", "Set Up >", {})
                    ])
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 400, height: 470)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 28, y: 10)
    }

    private func settingsGroup(
        title: String,
        rows: [(icon: String, color: Color, label: String, trailing: String, action: () -> Void)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            VStack(spacing: 0) {
                ForEach(0..<rows.count, id: \.self) { idx in
                    let row = rows[idx]
                    Button(action: row.action) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(row.color.opacity(0.15))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: row.icon)
                                        .font(.system(size: 13))
                                        .foregroundStyle(row.color)
                                )
                            Text(row.label)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(row.trailing)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if idx < rows.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
