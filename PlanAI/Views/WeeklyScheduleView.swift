import SwiftUI
import SwiftData

public struct WeeklyScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \WorkSlot.sortOrder) private var workSlots: [WorkSlot]

    private let schedulerService = WeeklySchedulerService()

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

            // Panel Derecho: Agenda y Diagnóstico de Avance
            VStack(spacing: 0) {
                if let result = scheduleResult {
                    diagnosticHeader(result: result)
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
            .frame(minWidth: 400)
        }
        .sheet(isPresented: $showingAddSlotSheet) {
            AddWorkSlotSheet { newSlot in
                modelContext.insert(newSlot)
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
    let onAdd: (WorkSlot) -> Void

    @State private var weekday: Int = 2 // Lunes
    @State private var startHour: Int = 9
    @State private var startMin: Int = 0
    @State private var endHour: Int = 13
    @State private var endMin: Int = 0
    @State private var label: String = ""

    private let weekdays = [
        (2, "Lunes"),
        (3, "Martes"),
        (4, "Miércoles"),
        (5, "Jueves"),
        (6, "Viernes"),
        (7, "Sábado"),
        (1, "Domingo")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "Día y Etiqueta"))) {
                    Picker(String(localized: "Día de la semana"), selection: $weekday) {
                        ForEach(weekdays, id: \.0) { item in
                            Text(item.1).tag(item.0)
                        }
                    }

                    TextField(String(localized: "Etiqueta (opcional, ej. Mañana foco)"), text: $label)
                }

                Section(header: Text(String(localized: "Horario"))) {
                    HStack {
                        Text(String(localized: "Hora de inicio:"))
                        Spacer()
                        Picker("", selection: $startHour) {
                            ForEach(6..<24) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .frame(width: 60)
                        Text(":")
                        Picker("", selection: $startMin) {
                            Text("00").tag(0)
                            Text("15").tag(15)
                            Text("30").tag(30)
                            Text("45").tag(45)
                        }
                        .frame(width: 60)
                    }

                    HStack {
                        Text(String(localized: "Hora de fin:"))
                        Spacer()
                        Picker("", selection: $endHour) {
                            ForEach(6..<24) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .frame(width: 60)
                        Text(":")
                        Picker("", selection: $endMin) {
                            Text("00").tag(0)
                            Text("15").tag(15)
                            Text("30").tag(30)
                            Text("45").tag(45)
                        }
                        .frame(width: 60)
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
                        let newSlot = WorkSlot(
                            weekday: weekday,
                            startMinute: startTotal,
                            endMinute: endTotal,
                            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                            isEnabled: true
                        )
                        onAdd(newSlot)
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 380, minHeight: 280)
        }
    }
}
