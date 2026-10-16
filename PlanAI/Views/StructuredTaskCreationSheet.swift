import SwiftUI
import SwiftData

public struct StructuredTaskDraft: Sendable {
    public var editingTaskId: UUID?
    public var projectId: UUID?
    public var title: String
    public var notes: String
    public var date: Date
    public var startMinute: Int
    public var durationMinutes: Int
    public var iconName: String
    public var colorToken: String
    public var alertOffsetMinutes: Int?
    public var subtasks: [String]
    public var isInbox: Bool

    public init(
        editingTaskId: UUID? = nil,
        projectId: UUID? = nil,
        title: String,
        notes: String = "",
        date: Date = Date(),
        startMinute: Int = 600,
        durationMinutes: Int = 15,
        iconName: String = "doc.fill",
        colorToken: String = "coral",
        alertOffsetMinutes: Int? = 5,
        subtasks: [String] = [],
        isInbox: Bool = false
    ) {
        self.editingTaskId = editingTaskId
        self.projectId = projectId
        self.title = title
        self.notes = notes
        self.date = date
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.iconName = iconName
        self.colorToken = colorToken
        self.alertOffsetMinutes = alertOffsetMinutes
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
    public var projects: [Project]
    public var taskToEdit: ProjectTask?
    public let onSave: (StructuredTaskDraft) -> Void
    public let onClose: () -> Void

    @State private var step: Int = 1
    @State private var taskTitle: String = ""
    @State private var taskNotes: String = ""
    @State private var selectedDate: Date
    @State private var startMinute: Int
    @State private var durationMinutes: Int = 30
    @State private var selectedIcon: String = "doc.fill"
    @State private var selectedColorToken: String = "coral"
    @State private var selectedProjectId: UUID?
    @State private var alertOffsetMinutes: Int? = 5
    @State private var subtasks: [String] = []
    @State private var newSubtaskText: String = ""
    @State private var showingIconPicker: Bool = false

    // Asistente rápido Structured AI (lenguaje natural)
    @State private var aiQuickPrompt: String = ""
    @State private var isParsingAIPrompt: Bool = false

    private let decompositionService = TaskDecompositionService()

    private let durationPresets: [(label: String, minutes: Int)] = [
        ("15m", 15),
        ("30m", 30),
        ("45m", 45),
        ("1h", 60),
        ("1.5h", 90),
        ("2h", 120)
    ]

    private let suggestions: [(title: String, timeRange: String, startMin: Int, duration: Int, icon: String, color: String)] = [
        ("Deep Work & Code", "9:00–10:00 (1 hr)", 540, 60, "laptopcomputer", "ocean"),
        ("Answer Emails", "10:00–10:15 (15 min)", 600, 15, "at", "coral"),
        ("Design & Wireframes", "10:30–11:30 (1 hr)", 630, 60, "paintbrush.fill", "lavender"),
        ("Team Sync", "11:30–12:00 (30 min)", 690, 30, "person.2.fill", "amber"),
        ("QA & Verification", "16:00–16:45 (45 min)", 960, 45, "checkmark.shield.fill", "teal")
    ]

    public init(
        initialDate: Date = Date(),
        initialStartMinute: Int = 600,
        isInboxMode: Bool = false,
        existingItemsForDay: [ScheduledItem] = [],
        projects: [Project] = [],
        taskToEdit: ProjectTask? = nil,
        onSave: @escaping (StructuredTaskDraft) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        self.initialDate = initialDate
        self.initialStartMinute = initialStartMinute
        self.isInboxMode = isInboxMode
        self.existingItemsForDay = existingItemsForDay
        self.projects = projects
        self.taskToEdit = taskToEdit
        self.onSave = onSave
        self.onClose = onClose

        if let edit = taskToEdit {
            self._step = State(initialValue: edit.isInbox ? 1 : 2)
            self._taskTitle = State(initialValue: edit.title)
            self._taskNotes = State(initialValue: edit.notes)
            self._selectedDate = State(initialValue: edit.scheduledDate ?? edit.startDate)
            let sMin = edit.fixedStartMinute ?? initialStartMinute
            let eMin = edit.fixedEndMinute ?? (sMin + max(15, Int(round(edit.estimatedHours * 60))))
            self._startMinute = State(initialValue: sMin)
            self._durationMinutes = State(initialValue: max(15, eMin - sMin))
            self._selectedIcon = State(initialValue: edit.iconName)
            self._selectedColorToken = State(initialValue: edit.effectiveColorToken)
            self._selectedProjectId = State(initialValue: edit.project?.id ?? projects.first?.id)
            self._alertOffsetMinutes = State(initialValue: edit.alertOffsetMinutes)
            self._subtasks = State(initialValue: edit.sortedSubtasks.map(\.title))
        } else {
            self._selectedDate = State(initialValue: initialDate)
            self._startMinute = State(initialValue: initialStartMinute)
            self._selectedProjectId = State(initialValue: projects.first?.id)
        }
    }

    private var activeThemeColor: Color {
        StructuredTheme.color(forToken: selectedColorToken)
    }

    private var activeThemeLightColor: Color {
        StructuredTheme.lightColor(forToken: selectedColorToken)
    }

    private var filteredSuggestions: [(title: String, timeRange: String, startMin: Int, duration: Int, icon: String, color: String)] {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return suggestions }
        return suggestions.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Detecta en vivo si el horario elegido colisiona con otra tarea existente en el mismo día (excluyendo la propia si se edita)
    private var hasOverlapConflict: Bool {
        guard !isInboxMode else { return false }
        let endMin = startMinute + durationMinutes
        return existingItemsForDay.contains { item in
            if let editingId = taskToEdit?.id, item.taskId == editingId {
                return false
            }
            return max(item.startMinute, startMinute) < min(item.endMinute, endMin)
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
            // CABECERA DINÁMICA CON COLOR E ICONO PERSONALIZABLES
            headerSection

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
        .frame(width: 365, height: step == 1 ? 475 : 515)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Cabecera Dinámica
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

                // Selector de Proyecto destino
                if !projects.isEmpty {
                    Menu {
                        ForEach(projects) { proj in
                            Button {
                                selectedProjectId = proj.id
                                selectedColorToken = proj.colorToken
                            } label: {
                                Label(proj.name, systemImage: proj.iconName)
                            }
                        }
                    } label: {
                        let currentProjName = projects.first(where: { $0.id == selectedProjectId })?.name ?? String(localized: "Proyecto")
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                            Text(currentProjName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.22))
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                }

                if isInboxMode {
                    Text(String(localized: "Inbox Task"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 14) {
                // Selector de icono y color circular
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
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Color"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(StructuredColorToken.allCases) { token in
                                Button {
                                    selectedColorToken = token.rawValue
                                } label: {
                                    Circle()
                                        .fill(token.primaryColor)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Image(systemName: selectedColorToken == token.rawValue ? "checkmark" : "")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(token.displayName)
                            }
                        }

                        Divider()

                        Text(String(localized: "Icono"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 4), spacing: 10) {
                            ForEach(StructuredTheme.curatedIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                    showingIconPicker = false
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(selectedIcon == icon ? .white : activeThemeColor)
                                        .frame(width: 34, height: 34)
                                        .background(selectedIcon == icon ? activeThemeColor : activeThemeLightColor)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if step > 1 && !isInboxMode {
                        Text(formattedTimeRangeHeader)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    HStack {
                        TextField(String(localized: "Nombre de la tarea..."), text: $taskTitle)
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
        .background(activeThemeColor)
    }

    // MARK: - PASO 1: Structured AI Quick Fill + Sugerencias en vivo
    private var stepOneSuggestionsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Barra de lenguaje natural Structured AI
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activeThemeColor)

                TextField(String(localized: "IA: ej. 'Diseño UI a las 11:30 por 45m'"), text: $aiQuickPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .onSubmit {
                        runAIQuickParse()
                    }

                if isParsingAIPrompt {
                    ProgressView()
                        .controlSize(.small)
                } else if !aiQuickPrompt.isEmpty {
                    Button {
                        runAIQuickParse()
                    } label: {
                        Text(String(localized: "Auto"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(activeThemeColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(activeThemeLightColor.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text(String(localized: "Sugerencias"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(filteredSuggestions, id: \.title) { item in
                        Button {
                            taskTitle = item.title
                            startMinute = item.startMin
                            durationMinutes = item.duration
                            selectedIcon = item.icon
                            selectedColorToken = item.color
                            advanceStep()
                        } label: {
                            let itemColor = StructuredTheme.color(forToken: item.color)
                            let itemLight = StructuredTheme.lightColor(forToken: item.color)
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(itemLight)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: item.icon)
                                            .font(.system(size: 15))
                                            .foregroundStyle(itemColor)
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
                Text(isInboxMode ? String(localized: "Guardar en Inbox") : String(localized: "Continuar"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(activeThemeColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - PASO 2: Fecha, Rueda de Hora y Barra de Duración
    private var stepTwoTimeAndDurationBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Spacer()
                Button(String(localized: "Hoy >")) {
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

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Horario"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    if hasOverlapConflict {
                        Label(String(localized: "Solapa con otra tarea"), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 18)

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
                    .background(activeThemeColor)
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

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Duración"))
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
                                .foregroundStyle(isSelected ? activeThemeColor : .secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
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
                Text(String(localized: "Continuar"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(activeThemeColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    // MARK: - PASO 3: Alertas, Subtareas, Notas y Confirmación
    private var stepThreeDetailsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            // Selector interactivo de Alerta / Nudge
            HStack {
                Image(systemName: alertOffsetMinutes == nil ? "bell.slash" : "bell.fill")
                    .foregroundStyle(alertOffsetMinutes == nil ? .secondary : activeThemeColor)
                Text(String(localized: "Alerta (Nudge)"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer()
                Picker("", selection: $alertOffsetMinutes) {
                    Text(String(localized: "Sin alerta")).tag(Int?.none)
                    Text(String(localized: "Al empezar")).tag(Int?.some(0))
                    Text(String(localized: "5 min antes")).tag(Int?.some(5))
                    Text(String(localized: "15 min antes")).tag(Int?.some(15))
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 125)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            // Subtareas ("+ Add Subtask")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(subtasks.enumerated()), id: \.offset) { idx, sub in
                    HStack(spacing: 8) {
                        Image(systemName: "square")
                            .foregroundStyle(activeThemeColor)
                        Text(sub)
                            .font(.system(size: 12, design: .rounded))
                        Spacer()
                        Button {
                            subtasks.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus.square")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Añadir subtarea..."), text: $newSubtaskText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .rounded))
                        .onSubmit {
                            addInlineSubtask()
                        }
                    if !newSubtaskText.isEmpty {
                        Button(String(localized: "Añadir")) {
                            addInlineSubtask()
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .buttonStyle(.plain)
                        .foregroundStyle(activeThemeColor)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)

            // Notas
            TextField(String(localized: "Añadir notas, enlaces de reunión o detalles..."), text: $taskNotes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .lineLimit(3...5)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)

            Spacer()

            Button(action: finalizeTaskCreation) {
                Text(taskToEdit != nil ? String(localized: "Guardar Cambios") : String(localized: "Crear Tarea"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(activeThemeColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func runAIQuickParse() {
        let prompt = aiQuickPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isParsingAIPrompt = true
        Task {
            let parsed = await decompositionService.parseQuickSchedulePrompt(prompt, defaultStartMinute: startMinute)
            await MainActor.run {
                taskTitle = parsed.title
                startMinute = parsed.startMinute
                durationMinutes = parsed.durationMinutes
                selectedIcon = parsed.iconName
                selectedColorToken = parsed.colorToken
                if !parsed.notes.isEmpty {
                    taskNotes = parsed.notes
                }
                if !parsed.subtasks.isEmpty {
                    subtasks = parsed.subtasks
                }
                aiQuickPrompt = ""
                isParsingAIPrompt = false
                advanceStep()
            }
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
            if !aiQuickPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runAIQuickParse()
                return
            }
            taskTitle = String(localized: "Nueva Tarea")
        }
        selectedIcon = selectedIcon == "doc.fill" ? TaskDecompositionService.inferIcon(for: taskTitle) : selectedIcon
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
            editingTaskId: taskToEdit?.id,
            projectId: selectedProjectId,
            title: finalTitle.isEmpty ? String(localized: "Nueva Tarea") : finalTitle,
            notes: taskNotes,
            date: selectedDate,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            iconName: selectedIcon,
            colorToken: selectedColorToken,
            alertOffsetMinutes: alertOffsetMinutes,
            subtasks: subtasks,
            isInbox: isInboxMode
        )
        onSave(draft)
        onClose()
    }
}
