import SwiftUI
import SwiftData

public struct DailyTimelineView: View {
    public let result: ScheduleResult
    public let workSlots: [WorkSlot]
    @Binding public var selectedDate: Date
    @Binding public var isSheetExpanded: Bool
    public var onToggleItem: (ScheduledItem) -> Void = { _ in }
    public var onAddNewTask: (Int?) -> Void = { _ in }
    public var onOpenAI: () -> Void = {}
    public var onDropInboxTask: (String) -> Void = { _ in }

    @State private var selectedItemForPopover: ScheduledItem?
    @State private var currentTime = Date()
    @GestureState private var dragTranslation: CGFloat = 0

    public init(
        result: ScheduleResult,
        workSlots: [WorkSlot],
        selectedDate: Binding<Date>,
        isSheetExpanded: Binding<Bool> = .constant(true),
        onToggleItem: @escaping (ScheduledItem) -> Void = { _ in },
        onAddNewTask: @escaping (Int?) -> Void = { _ in },
        onOpenAI: @escaping () -> Void = {},
        onDropInboxTask: @escaping (String) -> Void = { _ in }
    ) {
        self.result = result
        self.workSlots = workSlots
        self._selectedDate = selectedDate
        self._isSheetExpanded = isSheetExpanded
        self.onToggleItem = onToggleItem
        self.onAddNewTask = onAddNewTask
        self.onOpenAI = onOpenAI
        self.onDropInboxTask = onDropInboxTask
    }

    private var calendar: Calendar { Calendar.current }

    private var isViewingToday: Bool {
        calendar.isDateInToday(selectedDate)
    }

    private var currentMinuteOfDay: Int {
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)
        return hour * 60 + minute
    }

    private var dayItems: [ScheduledItem] {
        result.scheduledItems
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted {
                if $0.startMinute == $1.startMinute {
                    return ($0.endMinute - $0.startMinute) > ($1.endMinute - $1.startMinute)
                }
                return $0.startMinute < $1.startMinute
            }
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    // Tirador Superior Interactivo (Grab Handle)
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(StructuredTheme.grabHandleColor)
                            .frame(width: 44, height: 5)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            isSheetExpanded.toggle()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation.height
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    if value.translation.height > 40 {
                                        isSheetExpanded = false
                                    } else if value.translation.height < -30 {
                                        isSheetExpanded = true
                                    }
                                }
                            }
                    )

                    if isSheetExpanded {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                morningRoutineRow

                                if dayItems.isEmpty {
                                    emptyTimelineGap
                                } else {
                                    timelineTasksFlow
                                }

                                eveningRoutineRow
                                    .padding(.top, 16)
                                    .padding(.bottom, 60)
                            }
                            .padding(.leading, 32)
                            .padding(.trailing, 96)
                            .padding(.vertical, 8)
                        }
                    } else {
                        collapsedPreviewContent
                            .padding(.leading, 32)
                            .padding(.trailing, 96)
                            .padding(.bottom, 14)
                    }
                }
                .background(StructuredTheme.sheetBackground(for: .light))
                .clipShape(RoundedRectangle(cornerRadius: StructuredTheme.sheetCornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 18, y: -2)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .offset(y: max(-20, min(120, dragTranslation * 0.35)))
                .dropDestination(for: String.self) { droppedIds, _ in
                    if let firstId = droppedIds.first {
                        onDropInboxTask(firstId)
                        return true
                    }
                    return false
                }

                // Botón flotante coral (+) en la esquina inferior derecha
                Button {
                    onAddNewTask(nil)
                } label: {
                    ZStack {
                        Circle()
                            .fill(StructuredTheme.coral)
                            .frame(width: 54, height: 54)
                            .shadow(color: StructuredTheme.coral.opacity(0.40), radius: 8, y: 4)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 34)
                .padding(.bottom, 24)
                .help("Crear nueva tarea")
            }
            .onChange(of: timeline.date) { _, newDate in
                currentTime = newDate
            }
            .popover(item: $selectedItemForPopover) { item in
                ScheduledItemDetailPopover(
                    item: item,
                    subtaskNotes: nil,
                    taskNotes: nil,
                    onToggle: {
                        onToggleItem(item)
                        selectedItemForPopover = nil
                    },
                    onEdit: {
                        selectedItemForPopover = nil
                    }
                )
            }
        }
    }

    // MARK: - Vista Previa Colapsada (Vídeo 00:01 y 00:35)
    @ViewBuilder
    private var collapsedPreviewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dayItems.isEmpty {
                eveningRoutineRow
            } else {
                ForEach(Array(dayItems.prefix(2).enumerated()), id: \.element.id) { idx, item in
                    if idx == 1 && item.startMinute < dayItems[0].endMinute {
                        overlapWarningSection
                    }
                    taskRow(item: item, isCompactPreview: true)
                }
            }
        }
    }

    private var morningRoutineRow: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("6:15")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            ZStack {
                Circle()
                    .fill(StructuredTheme.coralLight)
                    .frame(width: 44, height: 44)
                Image(systemName: "alarm.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(StructuredTheme.coral)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("6:15 AM")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "Rise and Shine"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Circle()
                .stroke(StructuredTheme.coral, lineWidth: 2)
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private var timelineTasksFlow: some View {
        let items = dayItems
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let prevEndMinute = index == 0 ? 375 : items[index - 1].endMinute
            let gapMinutes = item.startMinute - prevEndMinute

            VStack(alignment: .leading, spacing: 0) {
                if gapMinutes < 0 {
                    overlapWarningSection
                } else {
                    gapSection(
                        gapMinutes: gapMinutes,
                        startMinute: prevEndMinute,
                        endMinute: item.startMinute
                    )
                }

                taskRow(item: item)
            }
        }
    }

    private var overlapWarningSection: some View {
        HStack(alignment: .center, spacing: 18) {
            Color.clear.frame(width: 44, height: 1)

            Path { path in
                path.move(to: CGPoint(x: 22, y: 0))
                path.addLine(to: CGPoint(x: 22, y: 20))
            }
            .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 3]))
            .frame(width: 44, height: 20)

            Text("Tasks are overlapping")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.red)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func taskRow(item: ScheduledItem, isCompactPreview: Bool = false) -> some View {
        let isCurrent = isViewingToday &&
            currentMinuteOfDay >= item.startMinute &&
            currentMinuteOfDay < item.endMinute &&
            !item.isCompleted
        let durationMins = max(15, item.endMinute - item.startMinute)
        let capsuleHeight: CGFloat = isCompactPreview
            ? 44
            : max(44, min(86, CGFloat(durationMins) * 1.1))

        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .trailing, spacing: capsuleHeight > 54 ? 16 : 2) {
                Text(WorkSlot.formatTime(minute: item.startMinute))
                    .font(.system(size: 11, weight: isCurrent ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? StructuredTheme.coral : .secondary)
                Text(WorkSlot.formatTime(minute: item.endMinute))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .trailing)

            Button {
                selectedItemForPopover = item
            } label: {
                ZStack {
                    Capsule()
                        .fill(item.isCompleted ? StructuredTheme.mint : (isCompactPreview ? StructuredTheme.coralLight : StructuredTheme.coral))
                        .frame(width: 44, height: capsuleHeight)

                    Image(systemName: item.iconName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? .white : (isCompactPreview ? StructuredTheme.coral : .white))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(WorkSlot.formatTime(minute: item.startMinute))–\(WorkSlot.formatTime(minute: item.endMinute)) (\(formatDuration(item.allocatedHours)))")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)

                    if let sub = item.subtaskTitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(StructuredTheme.coralLight)
                            .foregroundStyle(StructuredTheme.coral)
                            .clipShape(Capsule())
                    }
                }

                Text(item.taskTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onToggleItem(item)
            } label: {
                ZStack {
                    if item.isCompleted {
                        Circle()
                            .fill(StructuredTheme.mint)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .stroke(StructuredTheme.coral, lineWidth: 2)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func gapSection(gapMinutes: Int, startMinute: Int, endMinute: Int) -> some View {
        if gapMinutes >= 15 {
            HStack(alignment: .center, spacing: 18) {
                Color.clear.frame(width: 44, height: 1)

                Path { path in
                    path.move(to: CGPoint(x: 22, y: 0))
                    path.addLine(to: CGPoint(x: 22, y: 48))
                }
                .stroke(
                    StructuredTheme.coral.opacity(0.45),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4])
                )
                .frame(width: 44, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(gapFriendlyMessage(minutes: gapMinutes))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if gapMinutes >= 60 {
                        Button {
                            onAddNewTask(startMinute)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                Text(String(localized: "Add Task"))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(StructuredTheme.coralLight)
                            .foregroundStyle(StructuredTheme.coral)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyTimelineGap: some View {
        HStack(alignment: .center, spacing: 18) {
            Color.clear.frame(width: 44, height: 1)

            Path { path in
                path.move(to: CGPoint(x: 22, y: 0))
                path.addLine(to: CGPoint(x: 22, y: 80))
            }
            .stroke(
                StructuredTheme.coral.opacity(0.45),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4])
            )
            .frame(width: 44, height: 80)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "You've got the whole day ahead. Ready to schedule?"))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                Button {
                    onAddNewTask(600)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                        Text(String(localized: "Add Task"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(StructuredTheme.coralLight)
                    .foregroundStyle(StructuredTheme.coral)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var eveningRoutineRow: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .trailing, spacing: 10) {
                Text("9:45")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("10:45")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .trailing)

            ZStack {
                Capsule()
                    .fill(StructuredTheme.nightNavy.opacity(0.18))
                    .frame(width: 44, height: 54)
                Image(systemName: "moon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(StructuredTheme.nightNavy)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("9:45–10:45 PM (1 hr)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "Wind Down"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Circle()
                .stroke(StructuredTheme.nightNavy, lineWidth: 2)
                .frame(width: 20, height: 20)
        }
    }

    private func gapFriendlyMessage(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "Use \(hours)h \(mins)m, task approaching."
        } else {
            return "A well-spent \(mins)m interval."
        }
    }

    private func formatDuration(_ hours: Double) -> String {
        let totalMinutes = Int(round(hours * 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 {
            return "\(h) hr, \(m) min"
        } else if h > 0 {
            return "\(h) hr"
        } else {
            return "\(m) min"
        }
    }
}
