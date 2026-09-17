import SwiftUI
import SwiftData

public struct WeeklyScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \WorkSlot.sortOrder) private var workSlots: [WorkSlot]

    private let schedulerService = WeeklySchedulerService()

    public enum ScheduleDisplayMode: String, CaseIterable, Identifiable {
        case list
        case weeklyGrid
        case monthlyGrid

        public var id: String { rawValue }

        public var localizedLabel: String {
            switch self {
            case .list: return String(localized: "Lista")
            case .weeklyGrid: return String(localized: "Rejilla Semanal")
            case .monthlyGrid: return String(localized: "Rejilla Mensual")
            }
        }

        public var iconName: String {
            switch self {
            case .list: return "list.bullet"
            case .weeklyGrid: return "rectangle.split.3x3"
            case .monthlyGrid: return "calendar"
            }
        }
    }

    @State private var displayMode: ScheduleDisplayMode = .weeklyGrid
    @State private var showingAddSlotSheet: Bool = false
    @State private var selectedWeeks: Int = 2
    @State private var safetyBufferPercent: Double = 0.15
    @State private var scheduleResult: ScheduleResult?

    public init() {}

    public var body: some View {
        HSplitView {
            // Panel Izquierdo: Configuración de Disponibilidad Semanal
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Momentos Disponibles"))
                            .font(.headline)
                        Text(String(localized: "Define cuándo puedes avanzar proyectos en la semana."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { showingAddSlotSheet = true }) {
                        Label(String(localized: "Añadir Bloque"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                if workSlots.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "No has configurado ningún momento de trabajo."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Cargar plantilla típica (L-V)")) {
                            loadDefaultSlots()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(workSlots) { slot in
                            WorkSlotRow(slot: slot)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteSlot(slot)
                                    } label: {
                                        Label(String(localized: "Eliminar"), systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete(perform: deleteSlotOffsets)
                    }
                    .listStyle(.inset)
                }

                Divider()

                // Controles de optimización y despacho
                VStack(spacing: 10) {
                    HStack {
                        Text(String(localized: "Margen de seguridad:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $safetyBufferPercent) {
                            Text("10%").tag(0.10)
                            Text("15%").tag(0.15)
                            Text("20%").tag(0.20)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }

                    HStack {
                        Text(String(localized: "Horizonte temporal:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $selectedWeeks) {
                            Text("1 semana").tag(1)
                            Text("2 semanas").tag(2)
                            Text("4 semanas").tag(4)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }

                    Button(action: runOptimization) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(String(localized: "Asignar Tareas a Huecos"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .frame(minWidth: 320, idealWidth: 350, maxWidth: 450)

            // Panel Derecho: Agenda, Rejilla y Diagnóstico de Avance
            VStack(spacing: 0) {
                if let result = scheduleResult {
                    VStack(spacing: 8) {
                        diagnosticHeader(result: result)

                        HStack {
                            Spacer()
                            Picker("", selection: $displayMode) {
                                ForEach(ScheduleDisplayMode.allCases) { mode in
                                    Label(mode.localizedLabel, systemImage: mode.iconName)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 320)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    if result.scheduledItems.isEmpty {
                        ContentUnavailableView(
                            String(localized: "Sin tareas asignadas"),
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text(String(localized: "Asegúrate de tener proyectos con tareas pendientes y momentos de trabajo habilitados."))
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Group {
                            switch displayMode {
                            case .list:
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 14) {
                                        ForEach(groupedByDate(result.scheduledItems), id: \.date) { group in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(group.dateFormatted)
                                                    .font(.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(.primary)

                                                VStack(spacing: 6) {
                                                    ForEach(group.items) { item in
                                                        ScheduledItemCard(item: item)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding()
                                }

                            case .weeklyGrid:
                                WeeklyScheduleGridView(
                                    result: result,
                                    workSlots: workSlots,
                                    startDate: Date()
                                )

                            case .monthlyGrid:
                                MonthlyScheduleGridView(
                                    result: result,
                                    selectedDate: Date()
                                )
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "Asignación no calculada"),
                        systemImage: "calendar.badge.clock",
                        description: Text(String(localized: "Pulsa 'Asignar Tareas a Huecos' para encajar tus proyectos activos en tus momentos disponibles de forma segura y ordenada."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 450)
        }
        .sheet(isPresented: $showingAddSlotSheet) {
            AddWorkSlotSheet { newSlots in
                for slot in newSlots {
                    modelContext.insert(slot)
                }
                try? modelContext.save()
                runOptimization()
            }
        }
        .onAppear {
            if !workSlots.isEmpty {
                runOptimization()
            }
        }
    }

    // MARK: - Subvistas

    private func diagnosticHeader(result: ScheduleResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Plan de Avance Seguro"))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(String(format: String(localized: "Capacidad neta: %.1fh | Demanda: %.1fh"), result.totalAvailableHours, result.totalDemandHours))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if result.hasOverload {
                    Label {
                        Text(String(format: String(localized: "Déficit: %.1fh"), result.deficitHours))
                            .font(.caption)
                            .fontWeight(.bold)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                } else {
                    Label(String(localized: "Cumplimiento 100% viable"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
            }

            if !result.unscheduledTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Tareas pendientes sin hueco suficiente:"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    ForEach(result.unscheduledTasks.prefix(3)) { unscheduled in
                        HStack {
                            Text("• \(unscheduled.projectName): \(unscheduled.taskTitle)")
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1fh restantes", unscheduled.remainingHours))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Acciones y Helpers

    private func runOptimization() {
        scheduleResult = schedulerService.schedule(
            projects: projects,
            slots: workSlots,
            startDate: Date(),
            weeksToSchedule: selectedWeeks,
            safetyBufferPercent: safetyBufferPercent
        )
    }

    private func loadDefaultSlots() {
        for slot in WorkSlot.defaultSlots() {
            modelContext.insert(slot)
        }
        try? modelContext.save()
        runOptimization()
    }

    private func deleteSlot(_ slot: WorkSlot) {
        modelContext.delete(slot)
        try? modelContext.save()
        runOptimization()
    }

    private func deleteSlotOffsets(at offsets: IndexSet) {
        for index in offsets {
            let slot = workSlots[index]
            modelContext.delete(slot)
        }
        try? modelContext.save()
        runOptimization()
    }

    private struct DateGroup {
        let date: Date
        let dateFormatted: String
        let items: [ScheduledItem]
    }

    private func groupedByDate(_ items: [ScheduledItem]) -> [DateGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }

        let sortedKeys = grouped.keys.sorted()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return sortedKeys.map { key in
            DateGroup(
                date: key,
                dateFormatted: formatter.string(from: key),
                items: grouped[key] ?? []
            )
        }
    }
}

// MARK: - Fila de Bloque de Trabajo
struct WorkSlotRow: View {
    @Bindable var slot: WorkSlot
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $slot.isEnabled)
                .labelsHidden()
                .onChange(of: slot.isEnabled) { _, _ in
                    try? modelContext.save()
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(slot.weekdayName)
                        .fontWeight(.semibold)
                    if !slot.label.isEmpty {
                        Text("• \(slot.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(slot.startTimeFormatted) - \(slot.endTimeFormatted) (\(slot.durationFormatted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .opacity(slot.isEnabled ? 1.0 : 0.4)
        .padding(.vertical, 2)
    }
}

// MARK: - Tarjeta de Tarea Asignada
struct ScheduledItemCard: View {
    let item: ScheduledItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.projectName)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(item.timeRangeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(item.taskTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            Text(String(format: "%.1fh", item.allocatedHours))
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(4)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Modal para añadir un nuevo momento disponible
struct AddWorkSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: ([WorkSlot]) -> Void

    @State private var selectedWeekdays: Set<Int> = [2] // Lunes por defecto
    @State private var startHour: Int = 9
    @State private var startMin: Int = 0
    @State private var endHour: Int = 13
    @State private var endMin: Int = 0
    @State private var label: String = ""

    private let weekdays = [
        (2, "Lun", "Lunes"),
        (3, "Mar", "Martes"),
        (4, "Mié", "Miércoles"),
        (5, "Jue", "Jueves"),
        (6, "Vie", "Viernes"),
        (7, "Sáb", "Sábado"),
        (1, "Dom", "Domingo")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "Días de la Semana"))) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Atajos rápidos
                        HStack(spacing: 8) {
                            Button(String(localized: "L-V (Laborables)")) {
                                selectedWeekdays = [2, 3, 4, 5, 6]
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(String(localized: "Fin de semana")) {
                                selectedWeekdays = [7, 1]
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(String(localized: "Toda la semana")) {
                                selectedWeekdays = [2, 3, 4, 5, 6, 7, 1]
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()
                        }

                        // Selector de días interactivo tipo chips
                        HStack(spacing: 6) {
                            ForEach(weekdays, id: \.0) { item in
                                let isSelected = selectedWeekdays.contains(item.0)
                                Button {
                                    if isSelected {
                                        if selectedWeekdays.count > 1 {
                                            selectedWeekdays.remove(item.0)
                                        }
                                    } else {
                                        selectedWeekdays.insert(item.0)
                                    }
                                } label: {
                                    Text(item.1)
                                        .font(.caption)
                                        .fontWeight(isSelected ? .bold : .regular)
                                        .frame(minWidth: 34)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(item.2)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    TextField(String(localized: "Etiqueta (opcional, ej. Mañana foco)"), text: $label)
                }

                Section(header: Text(String(localized: "Horario"))) {
                    // Presets de horario
                    HStack(spacing: 8) {
                        Button("Mañana (9:00 - 13:00)") {
                            startHour = 9; startMin = 0
                            endHour = 13; endMin = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Tarde (16:00 - 20:00)") {
                            startHour = 16; startMin = 0
                            endHour = 20; endMin = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()
                    }

                    HStack {
                        Text(String(localized: "Hora de inicio:"))
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                        Picker("", selection: $startHour) {
                            ForEach(6..<24) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)

                        Text(":")
                            .fontWeight(.bold)

                        Picker("", selection: $startMin) {
                            Text("00").tag(0)
                            Text("15").tag(15)
                            Text("30").tag(30)
                            Text("45").tag(45)
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }

                    HStack {
                        Text(String(localized: "Hora de fin:"))
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                        Picker("", selection: $endHour) {
                            ForEach(6..<24) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)

                        Text(":")
                            .fontWeight(.bold)

                        Picker("", selection: $endMin) {
                            Text("00").tag(0)
                            Text("15").tag(15)
                            Text("30").tag(30)
                            Text("45").tag(45)
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Nuevo Momento Disponible"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancelar")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Añadir")) {
                        let startTotal = startHour * 60 + startMin
                        let endTotal = max(startTotal + 15, endHour * 60 + endMin)
                        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Crear un WorkSlot para cada día seleccionado
                        let createdSlots = selectedWeekdays.sorted().map { day in
                            WorkSlot(
                                weekday: day,
                                startMinute: startTotal,
                                endMinute: endTotal,
                                label: cleanLabel,
                                isEnabled: true
                            )
                        }

                        onAdd(createdSlots)
                        dismiss()
                    }
                    .disabled(selectedWeekdays.isEmpty)
                }
            }
            .frame(minWidth: 440, minHeight: 340)
        }
    }
}
