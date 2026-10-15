import SwiftUI

public struct StructuredTaskDraft: Sendable {
    public var title: String
    public var notes: String
    public var date: Date
    public var startMinute: Int
    public var durationMinutes: Int
    public var iconName: String
    public var subtasks: [String]
    public var isInbox: Bool

    public init(
        title: String,
        notes: String = "",
        date: Date = Date(),
        startMinute: Int = 600,
        durationMinutes: Int = 15,
        iconName: String = "doc.fill",
        subtasks: [String] = [],
        isInbox: Bool = false
    ) {
        self.title = title
        self.notes = notes
        self.date = date
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.iconName = iconName
        self.subtasks = subtasks
        self.isInbox = isInbox
    }

    public var endMinute: Int {
        startMinute + durationMinutes
    }
}

public struct StructuredTaskCreationSheet: View {
    public var initialDate: Date
    public var initialStartMinute: Int
    public var isInboxMode: Bool
    public var existingItemsForDay: [ScheduledItem]
    public let onSave: (StructuredTaskDraft) -> Void
    public let onClose: () -> Void

    @State private var step: Int = 1
    @State private var taskTitle: String = ""
    @State private var taskNotes: String = ""
    @State private var selectedDate: Date
    @State private var startMinute: Int
    @State private var durationMinutes: Int = 15
    @State private var selectedIcon: String = "doc.fill"
    @State private var subtasks: [String] = []
    @State private var newSubtaskText: String = ""
    @State private var showingIconPicker: Bool = false

    private let availableIcons = [
        "doc.fill", "at", "laptopcomputer", "person.2.fill",
        "paintbrush.fill", "figure.run", "cart.fill", "book.fill",
        "phone.fill", "sparkles", "terminal.fill", "checklist"
    ]

    private let durationPresets: [(label: String, minutes: Int)] = [
        ("1m", 1),
        ("15m", 15),
        ("30m", 30),
        ("45m", 45),
        ("1h", 60),
        ("1.5h", 90)
    ]

    private let suggestions: [(title: String, timeRange: String, startMin: Int, duration: Int, icon: String)] = [
        ("Prueba", "10:00–10:15 AM (15 min)", 600, 15, "doc.fill"),
        ("Answer Emails", "10:00–10:15 AM (15 min)", 600, 15, "at"),
        ("Watch a Movie", "8:00–9:30 PM (1 hr, 30 min)", 1200, 90, "tv.fill"),
        ("Deep Work & Code", "9:00–10:00 AM (1 hr)", 540, 60, "laptopcomputer"),
        ("Team Sync", "11:00–11:30 AM (30 min)", 660, 30, "person.2.fill")
    ]

    public init(
        initialDate: Date = Date(),
        initialStartMinute: Int = 600,
        isInboxMode: Bool = false,
        existingItemsForDay: [ScheduledItem] = [],
        onSave: @escaping (StructuredTaskDraft) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        self.initialDate = initialDate
        self.initialStartMinute = initialStartMinute
        self.isInboxMode = isInboxMode
        self.existingItemsForDay = existingItemsForDay
        self.onSave = onSave
        self.onClose = onClose
        self._selectedDate = State(initialValue: initialDate)
        self._startMinute = State(initialValue: initialStartMinute)
    }

    private var filteredSuggestions: [(title: String, timeRange: String, startMin: Int, duration: Int, icon: String)] {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return suggestions }
        return suggestions.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Detecta en vivo si el horario elegido colisiona con otra tarea existente en el mismo día (Mejora UX)
    private var hasOverlapConflict: Bool {
        guard !isInboxMode else { return false }
        let endMin = startMinute + durationMinutes
        return existingItemsForDay.contains { item in
            max(item.startMinute, startMinute) < min(item.endMinute, endMin)
        }
    }

    private var formattedTimeRangeHeader: String {
        let startStr = WorkSlot.formatTime(minute: startMinute)
        let endStr = WorkSlot.formatTime(minute: startMinute + durationMinutes)
        let durLabel = durationMinutes == 60 ? "1 hr" : "\(durationMinutes) min"
        return "\(startStr)–\(endStr) (\(durLabel))"
    }

    public var body: some View {
        VStack(spacing: 0) {
            // CABECERA CORAL (Cambia según el paso igual que en el vídeo 00:08 -> 00:15 -> 00:23)
            coralHeader

            // CUERPO POR PASOS
            Group {
                if step == 1 {
                    stepOneSuggestionsBody
                } else if step == 2 {
                    stepTwoTimeAndDurationBody
                } else {
                    stepThreeDetailsBody
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 350, height: step == 1 ? 420 : 490)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Cabecera Coral Dinámica
    private var coralHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                if isInboxMode {
                    Text("Inbox Task")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 14) {
                // Selector de icono circular
                Button {
                    showingIconPicker.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 50, height: 50)
                        Image(systemName: selectedIcon)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingIconPicker) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 4), spacing: 10) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                                showingIconPicker = false
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(selectedIcon == icon ? .white : StructuredTheme.coral)
                                    .frame(width: 34, height: 34)
                                    .background(selectedIcon == icon ? StructuredTheme.coral : StructuredTheme.coralLight)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if step > 1 && !isInboxMode {
                        Text(formattedTimeRangeHeader)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    HStack {
                        TextField("Answer Emails", text: $taskTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .onSubmit {
                                advanceStep()
                            }

                        if step > 1 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
                            } label: {
                                Image(systemName: "character.cursor.ibeam")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if step == 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(height: 1.5)
                    }
                }
            }
        }
        .padding(18)
        .background(StructuredTheme.coral)
    }

    // MARK: - PASO 1: Sugerencias en vivo (Vídeo 00:08 - 00:14)
    private var stepOneSuggestionsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Suggestions"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.top, 14)
                .padding(.horizontal, 18)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(filteredSuggestions, id: \.title) { item in
                        Button {
                            taskTitle = item.title
                            startMinute = item.startMin
                            durationMinutes = item.duration
                            selectedIcon = item.icon
                            advanceStep()
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(StructuredTheme.coralLight)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: item.icon)
                                            .font(.system(size: 15))
                                            .foregroundStyle(StructuredTheme.coral)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.timeRange)
                                        .font(.system(size: 10, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            Button(action: advanceStep) {
                Text(isInboxMode ? String(localized: "Create Inbox Task") : String(localized: "Continue"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(StructuredTheme.coral)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - PASO 2: Fecha, Rueda de Hora y Barra de Duración (Vídeo 00:15 - 00:22)
    private var stepTwoTimeAndDurationBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selector de Fecha ("Thu, Oct 15, 2026 | Today >")
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Spacer()
                Button("Today >") {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Rueda de Tiempo ("Time") estilo Structured (Vídeo 00:16 - 00:22)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Time")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    if hasOverlapConflict {
                        Label("Overlaps existing task", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 18)

                // Rueda visual interactiva en intervalos de 15 min
                VStack(spacing: 4) {
                    let prevMin = max(360, startMinute - 15)
                    let nextMin = min(1380, startMinute + 15)

                    Button {
                        withAnimation(.snappy) { startMinute = prevMin }
                    } label: {
                        Text(WorkSlot.formatTime(minute: prevMin))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    // Píldora central activa con ajuste rápido (-15m / +15m)
                    HStack(spacing: 14) {
                        Button {
                            withAnimation(.snappy) { startMinute = max(360, startMinute - 15) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)

                        Text("\(WorkSlot.formatTime(minute: startMinute))–\(WorkSlot.formatTime(minute: startMinute + durationMinutes))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()

                        Button {
                            withAnimation(.snappy) { startMinute = min(1380, startMinute + 15) }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
                    .background(StructuredTheme.coral)
                    .clipShape(Capsule())

                    Button {
                        withAnimation(.snappy) { startMinute = nextMin }
                    } label: {
                        Text(WorkSlot.formatTime(minute: nextMin))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }

            // Barra segmentada de Duración ("Duration": 1m, 15m, 30m, 45m, 1h, 1.5h - Vídeo 00:18)
            VStack(alignment: .leading, spacing: 6) {
                Text("Duration")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 18)

                HStack(spacing: 4) {
                    ForEach(durationPresets, id: \.minutes) { preset in
                        let isSelected = durationMinutes == preset.minutes
                        Button {
                            withAnimation(.snappy) {
                                durationMinutes = preset.minutes
                            }
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? StructuredTheme.coral : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.white : Color.clear)
                                        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0), radius: 3, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
                .padding(.horizontal, 16)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    step = 3
                }
            } label: {
                Text(String(localized: "Continue"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(StructuredTheme.coral)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - PASO 3: Subtareas, Notas y Confirmación ("Create Task" - Vídeo 00:23 - 00:29)
    private var stepThreeDetailsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Resumen Fecha y Hora clicable para volver al Paso 2
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { step = 2 }
            } label: {
                HStack {
                    Label(selectedDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Label("\(WorkSlot.formatTime(minute: startMinute))–\(WorkSlot.formatTime(minute: startMinute + durationMinutes))", systemImage: "clock")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.primary)
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Fila de Alerta (Vídeo 00:24)
            HStack {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
                Text("1 Alert")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Text("Nudge >")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            // Subtareas ("+ Add Subtask" - Vídeo 00:25)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(subtasks, id: \.self) { sub in
                    HStack(spacing: 8) {
                        Image(systemName: "square")
                            .foregroundStyle(StructuredTheme.coral)
                        Text(sub)
                            .font(.system(size: 12, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus.square")
                        .foregroundStyle(.secondary)
                    TextField("Add Subtask", text: $newSubtaskText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                        .onSubmit {
                            addInlineSubtask()
                        }
                    if !newSubtaskText.isEmpty {
                        Button("Add") {
                            addInlineSubtask()
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .buttonStyle(.plain)
                        .foregroundStyle(StructuredTheme.coral)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)

            // Notas ("Add notes, meeting links or phone numbers..." - Vídeo 00:26)
            TextField("Add notes, meeting links or phone numbers...", text: $taskNotes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .lineLimit(3...5)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)

            Spacer()

            Button(action: finalizeTaskCreation) {
                Text(String(localized: "Create Task"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(StructuredTheme.coral)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func addInlineSubtask() {
        let clean = newSubtaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        subtasks.append(clean)
        newSubtaskText = ""
    }

    private func advanceStep() {
        if taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            taskTitle = "Prueba"
        }
        if isInboxMode {
            finalizeTaskCreation()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                step = 2
            }
        }
    }

    private func finalizeTaskCreation() {
        addInlineSubtask()
        let finalTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = StructuredTaskDraft(
            title: finalTitle.isEmpty ? "Prueba" : finalTitle,
            notes: taskNotes,
            date: selectedDate,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            iconName: selectedIcon,
            subtasks: subtasks,
            isInbox: isInboxMode
        )
        onSave(draft)
        onClose()
    }
}

