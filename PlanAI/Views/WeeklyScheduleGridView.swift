import SwiftUI

/// Vista de rejilla semanal estilo horario escolar/calendario que muestra columnas por día y filas por horas.
public struct WeeklyScheduleGridView: View {
    public let result: ScheduleResult
    public let workSlots: [WorkSlot]
    public let startDate: Date
    public var onToggleItem: (ScheduledItem) -> Void = { _ in }

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
        onToggleItem: @escaping (ScheduledItem) -> Void = { _ in }
    ) {
        self.result = result
        self.workSlots = workSlots
        self.startDate = startDate
        self.onToggleItem = onToggleItem
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
                        .frame(minWidth: 140, maxWidth: .infinity)
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

                            // Tareas asignadas dentro de los bloques
                            ForEach(itemsForDay) { item in
                                let topOffset = offsetForMinute(item.startMinute)
                                let durationMin = max(15, item.endMinute - item.startMinute)
                                let height = heightForMinutes(durationMin)

                                ScheduledItemGridBlock(
                                    item: item,
                                    onToggle: {
                                        onToggleItem(item)
                                    }
                                )
                                .frame(height: max(22, height - 2))
                                .offset(y: topOffset + 1)
                                .padding(.horizontal, 4)
                            }
                        }
                        .frame(minWidth: 140, maxWidth: .infinity)
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

/// Bloque interactivo y estilizado para una tarea asignada en la rejilla
struct ScheduledItemGridBlock: View {
    let item: ScheduledItem
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(priorityColor(item.projectPriority))
                        .frame(width: 6, height: 6)

                    Text(item.projectName)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text(String(format: "%.1fh", item.allocatedHours))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(item.displayTitle)
                    .font(.system(size: 10, weight: .medium))
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                Text(item.timeRangeFormatted)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(priorityColor(item.projectPriority).opacity(0.4), lineWidth: 1)
        )
        .help("\(item.projectName): \(item.displayTitle) (\(item.timeRangeFormatted)) - Clic para marcar completada")
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
