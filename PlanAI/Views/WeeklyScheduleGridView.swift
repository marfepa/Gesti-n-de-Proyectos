import SwiftUI

/// Representa el posicionamiento visual de un ScheduledItem resuelto en columnas paralelas.
public struct PositionedScheduledItem: Identifiable, Sendable, Equatable {
    public let item: ScheduledItem
    public let columnIndex: Int
    public let totalColumns: Int

    public var id: UUID { item.id }

    public init(item: ScheduledItem, columnIndex: Int, totalColumns: Int) {
        self.item = item
        self.columnIndex = columnIndex
        self.totalColumns = totalColumns
    }
}

/// Vista de rejilla semanal estilo horario escolar/calendario que muestra columnas por día y filas por horas,
/// resolviendo solapamientos en columnas paralelas y ofreciendo popover de detalle.
public struct WeeklyScheduleGridView: View {
    public let result: ScheduleResult
    public let workSlots: [WorkSlot]
    public let startDate: Date
    public var onToggleItem: (ScheduledItem) -> Void = { _ in }
    public var onEditTask: (ProjectTask) -> Void = { _ in }

    @State private var selectedItem: ScheduledItem?
    @State private var taskForEditing: ProjectTask?

    private let startHourOfDay: Int = 8
    private let endHourOfDay: Int = 22
    private let hourRowHeight: CGFloat = 52.0

    private let dayNames = [
        (2, "Lunes"),
        (3, "Martes"),
        (4, "Miércoles"),
        (5, "Jueves"),
        (6, "Viernes"),
        (7, "Sábado"),
        (1, "Domingo")
    ]

    public init(
        result: ScheduleResult,
        workSlots: [WorkSlot],
        startDate: Date = Date(),
        onToggleItem: @escaping (ScheduledItem) -> Void = { _ in },
        onEditTask: @escaping (ProjectTask) -> Void = { _ in }
    ) {
        self.result = result
        self.workSlots = workSlots
        self.startDate = startDate
        self.onToggleItem = onToggleItem
        self.onEditTask = onEditTask
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Cabecera con días de la semana
                HStack(spacing: 0) {
                    Text("Hora")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 55, height: 32)
                        .background(Color(nsColor: .controlBackgroundColor))

                    ForEach(dayNames, id: \.0) { day in
                        VStack(spacing: 2) {
                            Text(day.1)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 160, maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            Rectangle()
                                .frame(width: 1)
                                .foregroundStyle(Color.gray.opacity(0.2)),
                            alignment: .trailing
                        )
                    }
                }
                .overlay(
                    Divider(),
                    alignment: .bottom
                )

                // Contenido de la cuadrícula: Horas vs Días
                HStack(alignment: .top, spacing: 0) {
                    // Columna de Horas
                    VStack(spacing: 0) {
                        ForEach(startHourOfDay..<endHourOfDay, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 55, height: hourRowHeight, alignment: .top)
                                .padding(.top, 4)
                                .overlay(
                                    Divider(),
                                    alignment: .bottom
                                )
                        }
                    }
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

                    // Columnas de Días
                    ForEach(dayNames, id: \.0) { day in
                        let weekdayNumber = day.0
                        let slotsForDay = workSlots.filter { $0.isEnabled && $0.weekday == weekdayNumber }
                        let calendar = Calendar.current
                        let itemsForDay = result.scheduledItems.filter {
                            calendar.component(.weekday, from: $0.date) == weekdayNumber
                        }
                        let positionedItems = layoutParallelColumns(for: itemsForDay)

                        ZStack(alignment: .topLeading) {
                            // Líneas divisorias horizontales por cada hora
                            VStack(spacing: 0) {
                                ForEach(startHourOfDay..<endHourOfDay, id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: hourRowHeight)
                                        .overlay(
                                            Divider().opacity(0.6),
                                            alignment: .bottom
                                        )
                                }
                            }

                            // Fondo para bloques disponibles (WorkSlots)
                            ForEach(slotsForDay) { slot in
                                let topOffset = offsetForMinute(slot.startMinute)
                                let height = heightForMinutes(slot.durationMinutes)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.blue.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    )
                                    .frame(height: max(16, height))
                                    .offset(y: topOffset)
                                    .padding(.horizontal, 2)
                            }

                            // Tareas asignadas dentro de los bloques con columnas paralelas
                            GeometryReader { colGeo in
                                let availableWidth = colGeo.size.width
                                ForEach(positionedItems) { positioned in
                                    let item = positioned.item
                                    let topOffset = offsetForMinute(item.startMinute)
                                    let durationMin = max(15, item.endMinute - item.startMinute)
                                    let height = heightForMinutes(durationMin)

                                    let totalCols = max(1, positioned.totalColumns)
                                    let colWidth = (availableWidth - 8.0) / CGFloat(totalCols)
                                    let xOffset = 4.0 + CGFloat(positioned.columnIndex) * colWidth

                                    ScheduledItemGridBlock(
                                        item: item,
                                        onToggle: {
                                            onToggleItem(item)
                                        },
                                        onSelect: {
                                            selectedItem = item
                                        }
                                    )
                                    .frame(width: max(40, colWidth - 4), height: max(24, height - 2))
                                    .offset(x: xOffset, y: topOffset + 1)
                                }
                            }
                        }
                        .frame(minWidth: 160, maxWidth: .infinity)
                        .frame(height: CGFloat(endHourOfDay - startHourOfDay) * hourRowHeight)
                        .overlay(
                            Rectangle()
                                .frame(width: 1)
                                .foregroundStyle(Color.gray.opacity(0.2)),
                            alignment: .trailing
                        )
                    }
                }
            }
        }
        .popover(item: $selectedItem) { item in
            ScheduledItemDetailPopover(
                item: item,
                subtaskNotes: nil,
                taskNotes: nil,
                onToggle: {
                    onToggleItem(item)
                    // Actualizar el estado local para reflejar el toggle en el popover
                    if var current = selectedItem, current.id == item.id {
                        current.isCompleted.toggle()
                        selectedItem = current
                    }
                },
                onEdit: {
                    selectedItem = nil
                    // Si se desea editar la tarea
                }
            )
        }
    }

    /// Calcula la distribución de items en columnas paralelas para evitar superposiciones.
    public nonisolated static func computeParallelColumns(items: [ScheduledItem]) -> [PositionedScheduledItem] {
        guard !items.isEmpty else { return [] }

        // Ordenar por hora de inicio, y a igual hora, por mayor duración
        let sorted = items.sorted {
            if $0.startMinute == $1.startMinute {
                return ($0.endMinute - $0.startMinute) > ($1.endMinute - $1.startMinute)
            }
            return $0.startMinute < $1.startMinute
        }

        // Agrupar items que se solapan en clusters conexos
        var clusters: [[ScheduledItem]] = []
        var currentCluster: [ScheduledItem] = []
        var clusterEnd = -1

        for item in sorted {
            if currentCluster.isEmpty {
                currentCluster.append(item)
                clusterEnd = item.endMinute
            } else {
                if item.startMinute < clusterEnd {
                    // Se solapa con el cluster actual
                    currentCluster.append(item)
                    clusterEnd = max(clusterEnd, item.endMinute)
                } else {
                    // Nuevo cluster independiente
                    clusters.append(currentCluster)
                    currentCluster = [item]
                    clusterEnd = item.endMinute
                }
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        var results: [PositionedScheduledItem] = []

        // Para cada cluster, asignar columnas greedy
        for cluster in clusters {
            var columnEndTimes: [Int] = [] // Tiempo en que se libera cada columna
            var assignments: [(item: ScheduledItem, column: Int)] = []

            for item in cluster {
                var placedCol: Int?
                for colIdx in 0..<columnEndTimes.count {
                    if item.startMinute >= columnEndTimes[colIdx] {
                        placedCol = colIdx
                        columnEndTimes[colIdx] = item.endMinute
                        break
                    }
                }

                if let col = placedCol {
                    assignments.append((item, col))
                } else {
                    assignments.append((item, columnEndTimes.count))
                    columnEndTimes.append(item.endMinute)
                }
            }

            let totalCols = max(1, columnEndTimes.count)
            for assign in assignments {
                results.append(PositionedScheduledItem(item: assign.item, columnIndex: assign.column, totalColumns: totalCols))
            }
        }

        return results
    }

    private func layoutParallelColumns(for items: [ScheduledItem]) -> [PositionedScheduledItem] {
        Self.computeParallelColumns(items: items)
    }

    private func offsetForMinute(_ minute: Int) -> CGFloat {
        let startGridMinute = startHourOfDay * 60
        let relativeMinute = max(0, minute - startGridMinute)
        let pixelsPerMinute = hourRowHeight / 60.0
        return CGFloat(relativeMinute) * pixelsPerMinute
    }

    private func heightForMinutes(_ minutes: Int) -> CGFloat {
        let pixelsPerMinute = hourRowHeight / 60.0
        return CGFloat(minutes) * pixelsPerMinute
    }
}

/// Bloque interactivo y estilizado para una tarea asignada en la rejilla con soporte para click y formato compacto
public struct ScheduledItemGridBlock: View {
    public let item: ScheduledItem
    public var onToggle: () -> Void = {}
    public var onSelect: () -> Void = {}

    public init(
        item: ScheduledItem,
        onToggle: @escaping () -> Void = {},
        onSelect: @escaping () -> Void = {}
    ) {
        self.item = item
        self.onToggle = onToggle
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            GeometryReader { geo in
                let isCompact = geo.size.height < 32.0

                HStack(alignment: isCompact ? .center : .top, spacing: 3) {
                    Button(action: onToggle) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 9))
                            .foregroundStyle(item.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, isCompact ? 0 : 1)

                    if isCompact {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(priorityColor(item.projectPriority))
                                .frame(width: 5, height: 5)

                            Text(item.displayTitle)
                                .font(.system(size: 9, weight: .semibold))
                                .strikethrough(item.isCompleted, color: .secondary)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(String(format: "%.1fh", item.allocatedHours))
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(priorityColor(item.projectPriority))
                                    .frame(width: 5, height: 5)

                                Text(item.projectName)
                                    .font(.system(size: 8, weight: .bold))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 0)

                                Text(String(format: "%.1fh", item.allocatedHours))
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(item.displayTitle)
                                .font(.system(size: 9, weight: .medium))
                                .strikethrough(item.isCompleted, color: .secondary)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .lineLimit(2)

                            Text(item.timeRangeFormatted)
                                .font(.system(size: 7.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(priorityColor(item.projectPriority).opacity(0.4), lineWidth: 1)
                )
            }
        }
        .buttonStyle(.plain)
        .help("\(item.projectName): \(item.displayTitle) (\(item.timeRangeFormatted)) - Clic para ver detalles")
    }

    private func priorityColor(_ priority: ProjectPriority) -> Color {
        switch priority {
        case .baja: return .gray
        case .media: return .blue
        case .alta: return .orange
        case .urgente: return .red
        }
    }
}
