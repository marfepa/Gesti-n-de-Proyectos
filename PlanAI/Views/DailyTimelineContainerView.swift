import SwiftUI
import SwiftData

public struct DailyTimelineContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \WorkSlot.sortOrder) private var workSlots: [WorkSlot]

    public var viewModel: ProjectViewModel?

    // Preferencias persistentes configurables desde Settings
    @AppStorage("structuredWakeUpMinute") private var wakeUpMinute: Int = 375      // 06:15
    @AppStorage("structuredWindDownMinute") private var windDownMinute: Int = 1305 // 21:45
    @AppStorage("structuredSafetyBuffer") private var safetyBufferPercent: Double = 0.15
    @AppStorage("structuredAccentTheme") private var accentColorToken: String = "coral"
    @AppStorage("structuredCalendarSync") private var calendarSyncEnabled: Bool = false
    @AppStorage("structuredNotificationsEnabled") private var notificationsEnabled: Bool = true

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isSheetExpanded: Bool = true
    @State private var showingTaskCreationPopover: Bool = false
    @State private var taskCreationStartMinute: Int = 600
    @State private var taskBeingEdited: ProjectTask?
    @State private var showingSettingsModal: Bool = false
    @State private var showingAddSlotSheet: Bool = false
    @State private var showingAISheet: Bool = false
    @State private var showingSearchBar: Bool = false
    @State private var searchQuery: String = ""

    @State private var calendarService = CalendarSyncService.shared
    private let schedulerService = WeeklySchedulerService()

    public init(viewModel: ProjectViewModel? = nil) {
        self.viewModel = viewModel
    }

    private var accentColor: Color {
        StructuredTheme.color(forToken: accentColorToken)
    }

    private var accentLightColor: Color {
        StructuredTheme.lightColor(forToken: accentColorToken)
    }

    private var scheduleResult: ScheduleResult {
        schedulerService.schedule(
            projects: projects,
            slots: workSlots,
            externalEvents: calendarSyncEnabled ? calendarService.externalEvents : [],
            startDate: DayStripView.mondayOfWeek(containing: selectedDate),
            weeksToSchedule: 8,
            safetyBufferPercent: safetyBufferPercent
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
                    accentColor: accentColor,
                    accentLightColor: accentLightColor,
                    onOpenAI: { showingAISheet = true },
                    onToggleSearch: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingSearchBar.toggle()
                            if !showingSearchBar {
                                searchQuery = ""
                            }
                        }
                    },
                    onOpenSettings: { showingSettingsModal = true }
                )

                // Barra de búsqueda rápida en línea cuando está activa
                if showingSearchBar {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "Filtrar tareas del día por título o proyecto..."), text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .rounded))
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(StructuredTheme.sheetBackground(for: colorScheme))
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // 2. Cuerpo: Tallos Semanales + Hoja Inferior
                if isSheetExpanded {
                    DailyTimelineView(
                        result: scheduleResult,
                        workSlots: workSlots,
                        selectedDate: $selectedDate,
                        isSheetExpanded: $isSheetExpanded,
                        searchFilter: searchQuery,
                        wakeUpMinute: wakeUpMinute,
                        windDownMinute: windDownMinute,
                        accentColor: accentColor,
                        accentLightColor: accentLightColor,
                        onToggleItem: { item in
                            toggleItemCompletion(item)
                        },
                        onToggleSubtask: { subtaskId in
                            toggleSubtaskById(subtaskId)
                        },
                        onEditItem: { item in
                            openEditPopover(for: item)
                        },
                        onAddNewTask: { suggestedMinute in
                            taskBeingEdited = nil
                            taskCreationStartMinute = suggestedMinute ?? schedulerService.findNextAvailableGap(
                                on: selectedDate,
                                durationMinutes: 30,
                                existingItems: itemsForSelectedDay,
                                wakeUpMinute: wakeUpMinute,
                                windDownMinute: windDownMinute
                            )
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingTaskCreationPopover = true
                            }
                        },
                        onOpenAI: {
                            showingAISheet = true
                        },
                        onDropInboxTask: { droppedTaskId, targetMinute in
                            scheduleDroppedInboxTask(taskIdString: droppedTaskId, targetMinute: targetMinute)
                        }
                    )
                } else {
                    VStack(spacing: 6) {
                        StructuredWeeklyStemsView(
                            selectedDate: $selectedDate,
                            scheduledItems: scheduleResult.scheduledItems,
                            wakeUpMinute: wakeUpMinute,
                            windDownMinute: windDownMinute,
                            accentColor: accentColor,
                            accentLightColor: accentLightColor,
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
                            searchFilter: searchQuery,
                            wakeUpMinute: wakeUpMinute,
                            windDownMinute: windDownMinute,
                            accentColor: accentColor,
                            accentLightColor: accentLightColor,
                            onToggleItem: { item in
                                toggleItemCompletion(item)
                            },
                            onToggleSubtask: { subtaskId in
                                toggleSubtaskById(subtaskId)
                            },
                            onEditItem: { item in
                                openEditPopover(for: item)
                            },
                            onAddNewTask: { suggestedMinute in
                                taskBeingEdited = nil
                                taskCreationStartMinute = suggestedMinute ?? schedulerService.findNextAvailableGap(
                                    on: selectedDate,
                                    durationMinutes: 30,
                                    existingItems: itemsForSelectedDay,
                                    wakeUpMinute: wakeUpMinute,
                                    windDownMinute: windDownMinute
                                )
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showingTaskCreationPopover = true
                                }
                            },
                            onOpenAI: {
                                showingAISheet = true
                            },
                            onDropInboxTask: { droppedTaskId, targetMinute in
                                scheduleDroppedInboxTask(taskIdString: droppedTaskId, targetMinute: targetMinute)
                            }
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .background(StructuredTheme.canvasBackground(for: colorScheme))

            // POPOVER FLOTANTE DERECHO DE CREACIÓN / EDICIÓN DE TAREA
            if showingTaskCreationPopover {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingTaskCreationPopover = false
                            taskBeingEdited = nil
                        }
                    }

                StructuredTaskCreationSheet(
                    initialDate: selectedDate,
                    initialStartMinute: taskCreationStartMinute,
                    isInboxMode: false,
                    existingItemsForDay: itemsForSelectedDay,
                    projects: projects,
                    taskToEdit: taskBeingEdited,
                    onSave: { draft in
                        saveOrUpdateTask(from: draft)
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingTaskCreationPopover = false
                            taskBeingEdited = nil
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
                    wakeUpMinute: $wakeUpMinute,
                    windDownMinute: $windDownMinute,
                    safetyBufferPercent: $safetyBufferPercent,
                    accentColorToken: $accentColorToken,
                    calendarSyncEnabled: $calendarSyncEnabled,
                    notificationsEnabled: $notificationsEnabled,
                    onManageWorkSlots: {
                        showingSettingsModal = false
                        showingAddSlotSheet = true
                    },
                    onOpenAIProjectCreator: {
                        showingSettingsModal = false
                        showingAISheet = true
                    },
                    onToggleCalendarSync: { enabled in
                        if enabled {
                            Task {
                                let granted = await calendarService.requestAccessAndFetch(around: selectedDate)
                                if !granted {
                                    calendarSyncEnabled = false
                                }
                            }
                        }
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
            if calendarSyncEnabled {
                calendarService.fetchEvents(around: selectedDate)
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            if calendarSyncEnabled {
                calendarService.fetchEvents(around: newDate)
            }
        }
    }

    private func openEditPopover(for item: ScheduledItem) {
        guard !item.isExternalCalendarEvent else { return }
        for project in projects {
            if let task = project.tasks.first(where: { $0.id == item.taskId }) {
                taskBeingEdited = task
                taskCreationStartMinute = item.startMinute
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingTaskCreationPopover = true
                }
                return
            }
        }
    }

    private func saveOrUpdateTask(from draft: StructuredTaskDraft) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: draft.date)
        let taskStart = calendar.date(byAdding: .minute, value: draft.startMinute, to: dayStart) ?? dayStart
        let taskEnd = calendar.date(byAdding: .minute, value: draft.endMinute, to: dayStart) ?? dayStart
        let hours = max(0.05, Double(draft.durationMinutes) / 60.0)

        // Si estamos editando una tarea existente
        if let editId = draft.editingTaskId {
            for proj in projects {
                if let existing = proj.tasks.first(where: { $0.id == editId }) {
                    existing.title = draft.title
                    existing.notes = draft.notes
                    existing.startDate = taskStart
                    existing.endDate = max(taskStart, taskEnd)
                    existing.estimatedHours = hours
                    existing.scheduledDate = dayStart
                    existing.hasFixedTime = !draft.isInbox
                    existing.isInbox = draft.isInbox
                    existing.fixedStartMinute = draft.isInbox ? nil : draft.startMinute
                    existing.fixedEndMinute = draft.isInbox ? nil : draft.endMinute
                    existing.iconName = draft.iconName
                    existing.colorToken = draft.colorToken
                    existing.alertOffsetMinutes = draft.alertOffsetMinutes

                    // Sincronizar subtareas
                    for oldSub in existing.subtasks {
                        modelContext.delete(oldSub)
                    }
                    existing.subtasks.removeAll()
                    for (idx, subTitle) in draft.subtasks.enumerated() {
                        let sub = ProjectSubtask(
                            title: subTitle,
                            estimatedHours: max(0.25, hours / Double(max(1, draft.subtasks.count))),
                            sortOrder: idx,
                            task: existing
                        )
                        modelContext.insert(sub)
                        existing.subtasks.append(sub)
                    }

                    try? modelContext.save()
                    if notificationsEnabled {
                        Task { await NotificationService.shared.scheduleNotification(for: existing) }
                    }
                    return
                }
            }
        }

        let targetProject: Project
        if let pid = draft.projectId, let found = projects.first(where: { $0.id == pid }) {
            targetProject = found
        } else if let first = projects.first {
            targetProject = first
        } else {
            let newProject = Project(
                name: "Structured Timeline",
                projectDescription: "Tareas diarias y proyectos",
                priority: .media,
                colorToken: draft.colorToken
            )
            modelContext.insert(newProject)
            targetProject = newProject
        }

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
            colorToken: draft.colorToken,
            alertOffsetMinutes: draft.alertOffsetMinutes,
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
        if notificationsEnabled {
            Task { await NotificationService.shared.scheduleNotification(for: newTask) }
        }
    }

    private func scheduleDroppedInboxTask(taskIdString: String, targetMinute: Int?) {
        guard let uuid = UUID(uuidString: taskIdString) else { return }
        for project in projects {
            if let task = project.tasks.first(where: { $0.id == uuid }) {
                let durationMins = max(15, Int(round(task.effectiveEstimatedHours * 60)))
                let resolvedStart = targetMinute ?? schedulerService.findNextAvailableGap(
                    on: selectedDate,
                    durationMinutes: durationMins,
                    existingItems: itemsForSelectedDay,
                    wakeUpMinute: wakeUpMinute,
                    windDownMinute: windDownMinute
                )
                task.isInbox = false
                task.hasFixedTime = true
                task.scheduledDate = Calendar.current.startOfDay(for: selectedDate)
                task.fixedStartMinute = resolvedStart
                task.fixedEndMinute = min(1425, resolvedStart + durationMins)
                try? modelContext.save()
                if notificationsEnabled {
                    Task { await NotificationService.shared.scheduleNotification(for: task) }
                }
                return
            }
        }
    }

    private func toggleSubtaskById(_ subtaskId: UUID) {
        for project in projects {
            for task in project.tasks {
                if let sub = task.subtasks.first(where: { $0.id == subtaskId }) {
                    sub.isCompleted.toggle()
                    let allCompleted = task.subtasks.allSatisfy { $0.isCompleted }
                    if allCompleted && !task.subtasks.isEmpty {
                        task.isCompleted = true
                    } else if !sub.isCompleted {
                        task.isCompleted = false
                    }
                    try? modelContext.save()
                    return
                }
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
                        NotificationService.shared.cancelNotification(for: task.id)
                    }
                    try? modelContext.save()
                    return
                }
            }
        }
    }
}

// MARK: - Vista Semanal de Tallos Verticales Calibrada
public struct StructuredWeeklyStemsView: View {
    @Binding public var selectedDate: Date
    public let scheduledItems: [ScheduledItem]
    public var wakeUpMinute: Int = 375
    public var windDownMinute: Int = 1305
    public var accentColor: Color = StructuredTheme.coral
    public var accentLightColor: Color = StructuredTheme.coralLight
    public var onSelectDay: (Date) -> Void

    private var startHour: Int { max(5, min(9, wakeUpMinute / 60)) }
    private var endHour: Int { max(20, min(23, (windDownMinute + 60) / 60)) }
    private let topPad: CGFloat = 16
    private let bottomPad: CGFloat = 24
    private var calendar: Calendar { Calendar.current }

    private var daysInWeek: [Date] {
        let monday = DayStripView.mondayOfWeek(containing: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func yPosition(forMinute minute: Int, totalHeight: CGFloat) -> CGFloat {
        let trackHeight = max(180, totalHeight - topPad - bottomPad)
        let minMinute = CGFloat(startHour * 60)
        let maxMinute = CGFloat(endHour * 60)
        let clamped = max(minMinute, min(maxMinute, CGFloat(minute)))
        let ratio = (clamped - minMinute) / max(1, maxMinute - minMinute)
        return topPad + ratio * trackHeight
    }

    public var body: some View {
        GeometryReader { geo in
            let totalHeight = max(240, geo.size.height - 6)

            HStack(alignment: .top, spacing: 0) {
                // 1. Regla de horas graduada a la izquierda
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
        let isToday = calendar.isDateInToday(date)
        let startY = yPosition(forMinute: startHour * 60, totalHeight: totalHeight)
        let endY = yPosition(forMinute: endHour * 60, totalHeight: totalHeight)
        let capsules = computeStemCapsules(for: date, totalHeight: totalHeight)

        ZStack(alignment: .top) {
            Rectangle()
                .fill(isSelected ? accentColor.opacity(0.65) : Color.secondary.opacity(0.25))
                .frame(width: 2.5, height: max(10, endY - startY))
                .offset(y: startY)

            Circle()
                .fill(accentLightColor)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accentColor)
                )
                .offset(y: startY - 13)

            ForEach(capsules) { cap in
                let capColor = cap.item.isCompleted
                    ? StructuredTheme.mint
                    : StructuredTheme.color(forToken: cap.item.colorToken)
                ZStack {
                    Capsule()
                        .fill(capColor)
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

            // Indicador horizontal de hora actual ("Now") en el tallo de Hoy
            if isToday {
                let nowMin = calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
                let nowY = yPosition(forMinute: nowMin, totalHeight: totalHeight)
                HStack(spacing: 2) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 32, height: 1.5)
                }
                .offset(y: nowY)
            }

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

// MARK: - Modal Interactivo de Settings
public struct StructuredSettingsModalView: View {
    @Binding public var wakeUpMinute: Int
    @Binding public var windDownMinute: Int
    @Binding public var safetyBufferPercent: Double
    @Binding public var accentColorToken: String
    @Binding public var calendarSyncEnabled: Bool
    @Binding public var notificationsEnabled: Bool

    public var onManageWorkSlots: () -> Void
    public var onOpenAIProjectCreator: () -> Void
    public var onToggleCalendarSync: (Bool) -> Void
    public var onClose: () -> Void

    private var accentColor: Color {
        StructuredTheme.color(forToken: accentColorToken)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(String(localized: "Ajustes de PlanAI & Structured"))
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
                    // Banner Apple Intelligence
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 24))
                                .foregroundStyle(accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PlanAI + Apple Intelligence")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Text(String(localized: "Descompón proyectos en fases, iconos y subtareas con inferencia 100% privada en el dispositivo."))
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button(action: onOpenAIProjectCreator) {
                            Text(String(localized: "Crear Proyecto con Apple Intelligence"))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(accentColor)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(StructuredTheme.lightColor(forToken: accentColorToken).opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Tema de Color (Customization)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Tema de Color (Customization)"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)

                        HStack(spacing: 12) {
                            ForEach(StructuredColorToken.allCases) { token in
                                Button {
                                    accentColorToken = token.rawValue
                                } label: {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(token.primaryColor)
                                            .frame(width: 26, height: 26)
                                            .overlay(
                                                Image(systemName: accentColorToken == token.rawValue ? "checkmark" : "")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            )
                                        Text(token.displayName)
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Rutinas Diarias y Bloques de Trabajo
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Rutinas y Horario"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)

                        VStack(spacing: 0) {
                            HStack {
                                Label(String(localized: "Rise & Shine (Despertar)"), systemImage: "alarm.fill")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $wakeUpMinute) {
                                    Text("06:00").tag(360)
                                    Text("06:15").tag(375)
                                    Text("07:00").tag(420)
                                    Text("07:30").tag(450)
                                    Text("08:00").tag(480)
                                    Text("08:30").tag(510)
                                }
                                .frame(width: 90)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Divider().padding(.leading, 36)

                            HStack {
                                Label(String(localized: "Wind Down (Desconexión)"), systemImage: "moon.fill")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $windDownMinute) {
                                    Text("20:30").tag(1230)
                                    Text("21:00").tag(1260)
                                    Text("21:45").tag(1305)
                                    Text("22:00").tag(1320)
                                    Text("22:30").tag(1350)
                                }
                                .frame(width: 90)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Divider().padding(.leading, 36)

                            Button(action: onManageWorkSlots) {
                                HStack {
                                    Label(String(localized: "Momentos Disponibles (Work Slots)"), systemImage: "clock.fill")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                    Spacer()
                                    Text(String(localized: "Configurar >"))
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Energy Monitor (SafeLoad) & Integraciones macOS
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "SafeLoad & Integraciones del Sistema"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)

                        VStack(spacing: 0) {
                            HStack {
                                Label(String(localized: "Margen SafeLoad (Buffer)"), systemImage: "bolt.heart.fill")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                Spacer()
                                Picker("", selection: $safetyBufferPercent) {
                                    Text("10%").tag(0.10)
                                    Text("15%").tag(0.15)
                                    Text("20%").tag(0.20)
                                    Text("25%").tag(0.25)
                                }
                                .frame(width: 90)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Divider().padding(.leading, 36)

                            Toggle(isOn: $notificationsEnabled) {
                                Label(String(localized: "Alertas y Notificaciones Nativas"), systemImage: "bell.badge.fill")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .onChange(of: notificationsEnabled) { _, enabled in
                                if enabled {
                                    Task { _ = await NotificationService.shared.requestAuthorizationIfNeeded() }
                                }
                            }

                            Divider().padding(.leading, 36)

                            Toggle(isOn: $calendarSyncEnabled) {
                                Label(String(localized: "Sincronizar con Apple Calendar"), systemImage: "calendar.badge.clock")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .onChange(of: calendarSyncEnabled) { _, enabled in
                                onToggleCalendarSync(enabled)
                            }
                        }
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 420, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 28, y: 10)
    }
}
