import SwiftUI
import AppKit

public struct GanttChartView: View {
    public let tasks: [ProjectTask]
    @Binding public var selectedTask: ProjectTask?
    public let onEditTask: (ProjectTask) -> Void
    public var onTaskDateChanged: ((ProjectTask, Date, Date) -> Void)?

    @State private var showSubtasksInGantt: Bool = true
    @State private var draggingTask: ProjectTask?
    @State private var dragMode: DragMode = .none
    @State private var dragCurrentX: CGFloat = 0
    @State private var dragStartX: CGFloat = 0
    @State private var dragPreviewStart: Date?
    @State private var dragPreviewEnd: Date?

    private enum DragMode {
        case none
        case resizeStart
        case resizeEnd
        case move
    }

    private let rowHeight: CGFloat = 38.0
    private let handleWidth: CGFloat = 10.0
    private let leftColumnWidth: CGFloat = 200.0

    public init(
        tasks: [ProjectTask],
        selectedTask: Binding<ProjectTask?>,
        onEditTask: @escaping (ProjectTask) -> Void,
        onTaskDateChanged: ((ProjectTask, Date, Date) -> Void)? = nil
    ) {
        self.tasks = tasks
        self._selectedTask = selectedTask
        self.onEditTask = onEditTask
        self.onTaskDateChanged = onTaskDateChanged
    }

    /// Estructura aplanada para listar y graficar tareas y subtareas en filas
    private struct GanttChartItem: Identifiable {
        let id: String
        let title: String
        let parentTitle: String?
        let startDate: Date
        let endDate: Date
        let isCompleted: Bool
        let isSubtask: Bool
        let taskRef: ProjectTask
    }

    private var chartItems: [GanttChartItem] {
        var items: [GanttChartItem] = []

        for task in tasks {
            items.append(
                GanttChartItem(
                    id: task.id.uuidString,
                    title: task.title,
                    parentTitle: nil,
                    startDate: (draggingTask?.id == task.id && dragPreviewStart != nil) ? dragPreviewStart! : task.startDate,
                    endDate: (draggingTask?.id == task.id && dragPreviewEnd != nil) ? dragPreviewEnd! : task.endDate,
                    isCompleted: task.isCompleted,
                    isSubtask: false,
                    taskRef: task
                )
            )

            if showSubtasksInGantt && !task.subtasks.isEmpty {
                let subtasks = task.sortedSubtasks
                let totalSubtasks = max(1, subtasks.count)
                let effectiveStart = (draggingTask?.id == task.id && dragPreviewStart != nil) ? dragPreviewStart! : task.startDate
                let effectiveEnd = (draggingTask?.id == task.id && dragPreviewEnd != nil) ? dragPreviewEnd! : task.endDate
                let taskSpan = max(1.0, effectiveEnd.timeIntervalSince(effectiveStart))
                let slice = taskSpan / Double(totalSubtasks)

                for (idx, subtask) in subtasks.enumerated() {
                    let subStart = effectiveStart.addingTimeInterval(Double(idx) * slice)
                    let subEnd = effectiveStart.addingTimeInterval(Double(idx + 1) * slice)

                    items.append(
                        GanttChartItem(
                            id: subtask.id.uuidString,
                            title: "  ↳ \(subtask.title)",
                            parentTitle: task.title,
                            startDate: subStart,
                            endDate: subEnd,
                            isCompleted: subtask.isCompleted,
                            isSubtask: true,
                            taskRef: task
                        )
                    )
                }
            }
        }
        return items
    }

    private var timeScale: GanttTimeScale {
        GanttTimeScale(tasks: tasks)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cabecera y leyenda
            HStack {
                Text(String(localized: "Cronograma de Fases (Gantt Interactivo)"))
                    .font(.headline)

                Spacer()

                HStack(spacing: 16) {
                    Toggle(String(localized: "Ver subtareas"), isOn: $showSubtasksInGantt)
                        .font(.caption)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "En progreso"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "Completada"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                        Text(String(localized: "Subtarea"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            if tasks.isEmpty {
                ContentUnavailableView(
                    String(localized: "Sin tareas en el cronograma"),
                    systemImage: "calendar.badge.clock",
                    description: Text(String(localized: "Añade tareas manualmente o genera el plan con IA."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let scale = timeScale
                let items = chartItems
                let contentWidth = max(700, CGFloat(scale.totalDays * 32))

                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Regla temporal superior (Ticks semanales / fechas)
                        HStack(spacing: 0) {
                            Text(String(localized: "Fases / Tareas"))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(width: leftColumnWidth, alignment: .leading)
                                .padding(.leading, 12)

                            ZStack(alignment: .bottomLeading) {
                                ForEach(scale.ticks, id: \.self) { tick in
                                    let x = scale.xPosition(for: tick, totalWidth: contentWidth)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(formatDate(tick))
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 1, height: 8)
                                    }
                                    .offset(x: x)
                                }
                            }
                            .frame(width: contentWidth, height: 32)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(Divider(), alignment: .bottom)

                        // Filas de tareas
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 0) {
                                // Columna izquierda: Título y duración
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: item.isSubtask ? 11 : 12, weight: item.isSubtask ? .regular : .semibold))
                                        .foregroundStyle(item.isSubtask ? .secondary : .primary)
                                        .lineLimit(1)

                                    Spacer()

                                    if !item.isSubtask {
                                        Text("\(item.taskRef.durationInDays)d")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.trailing, 8)
                                    }
                                }
                                .frame(width: leftColumnWidth, height: rowHeight, alignment: .leading)
                                .padding(.leading, 12)
                                .background(index % 2 == 0 ? Color.clear : Color(nsColor: .separatorColor).opacity(0.04))
                                .overlay(
                                    Rectangle()
                                        .frame(width: 1)
                                        .foregroundStyle(Color.gray.opacity(0.15)),
                                    alignment: .trailing
                                )

                                // Área de trazado de barras
                                ZStack(alignment: .leading) {
                                    // Líneas verticales de rejilla
                                    ForEach(scale.ticks, id: \.self) { tick in
                                        let x = scale.xPosition(for: tick, totalWidth: contentWidth)
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.12))
                                            .frame(width: 1)
                                            .offset(x: x)
                                    }

                                    // Línea indicadora de Hoy
                                    if scale.isTodayVisible {
                                        let todayX = scale.xPosition(for: scale.today, totalWidth: contentWidth)
                                        Rectangle()
                                            .fill(Color.red.opacity(0.6))
                                            .frame(width: 1.5)
                                            .offset(x: todayX)
                                    }

                                    // Barra interactiva de la tarea o subtarea
                                    renderBar(for: item, totalWidth: contentWidth, scale: scale)
                                }
                                .frame(width: contentWidth, height: rowHeight)
                                .background(index % 2 == 0 ? Color.clear : Color(nsColor: .separatorColor).opacity(0.04))
                            }
                            .overlay(Divider().opacity(0.4), alignment: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func renderBar(for item: GanttChartItem, totalWidth: CGFloat, scale: GanttTimeScale) -> some View {
        let startX = scale.xPosition(for: item.startDate, totalWidth: totalWidth)
        let endX = scale.xPosition(for: item.endDate, totalWidth: totalWidth)
        let barWidth = max(12.0, endX - startX)
        let isCurrentDragging = draggingTask?.id == item.taskRef.id

        ZStack(alignment: .leading) {
            // Cuerpo de la barra
            RoundedRectangle(cornerRadius: item.isSubtask ? 3 : 6)
                .fill(barColor(for: item))
                .overlay(
                    RoundedRectangle(cornerRadius: item.isSubtask ? 3 : 6)
                        .stroke(isCurrentDragging ? Color.white : Color.clear, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(isCurrentDragging ? 0.2 : 0.05), radius: 2, y: 1)

            // Contenido interior de la barra
            HStack {
                Text(item.title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)

                Spacer(minLength: 0)
            }

            // Handles de redimensionamiento (solo para tareas principales)
            if !item.isSubtask {
                // Handle Izquierdo (ajustar fecha inicio)
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: handleWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                startDragging(task: item.taskRef, mode: .resizeStart, scale: scale, totalWidth: totalWidth, translation: value.translation.width)
                            }
                            .onEnded { _ in
                                endDragging(scale: scale, totalWidth: totalWidth)
                            }
                    )
                    .onHover { isHovering in
                        if isHovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }

                // Handle Derecho (ajustar fecha fin)
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: handleWidth)
                    .offset(x: barWidth - handleWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                startDragging(task: item.taskRef, mode: .resizeEnd, scale: scale, totalWidth: totalWidth, translation: value.translation.width)
                            }
                            .onEnded { _ in
                                endDragging(scale: scale, totalWidth: totalWidth)
                            }
                    )
                    .onHover { isHovering in
                        if isHovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }
        }
        .frame(width: barWidth, height: item.isSubtask ? 16 : 24)
        .offset(x: startX)
        .gesture(
            // Drag en el cuerpo para mover la tarea completa
            item.isSubtask ? nil : DragGesture()
                .onChanged { value in
                    startDragging(task: item.taskRef, mode: .move, scale: scale, totalWidth: totalWidth, translation: value.translation.width)
                }
                .onEnded { _ in
                    endDragging(scale: scale, totalWidth: totalWidth)
                }
        )
        .onTapGesture {
            selectedTask = item.taskRef
            if !item.isSubtask {
                onEditTask(item.taskRef)
            }
        }
    }

    private func startDragging(task: ProjectTask, mode: DragMode, scale: GanttTimeScale, totalWidth: CGFloat, translation: CGFloat) {
        self.draggingTask = task
        self.dragMode = mode

        let startX = scale.xPosition(for: task.startDate, totalWidth: totalWidth)
        let endX = scale.xPosition(for: task.endDate, totalWidth: totalWidth)

        switch mode {
        case .resizeStart:
            let newX = max(0, startX + translation)
            let rawDate = scale.date(forX: newX, totalWidth: totalWidth)
            let snapped = scale.snapToDay(rawDate)
            let minEnd = Calendar.current.date(byAdding: .day, value: 1, to: snapped) ?? snapped
            if snapped < task.endDate {
                self.dragPreviewStart = snapped
                self.dragPreviewEnd = max(minEnd, task.endDate)
            }

        case .resizeEnd:
            let newX = min(totalWidth, endX + translation)
            let rawDate = scale.date(forX: newX, totalWidth: totalWidth)
            let snapped = scale.snapToDay(rawDate)
            if snapped > task.startDate {
                self.dragPreviewStart = task.startDate
                self.dragPreviewEnd = snapped
            }

        case .move:
            let durationSeconds = task.endDate.timeIntervalSince(task.startDate)
            let newStartX = max(0, startX + translation)
            let rawStartDate = scale.date(forX: newStartX, totalWidth: totalWidth)
            let snappedStart = scale.snapToDay(rawStartDate)
            let snappedEnd = snappedStart.addingTimeInterval(durationSeconds)
            self.dragPreviewStart = snappedStart
            self.dragPreviewEnd = snappedEnd

        case .none:
            break
        }
    }

    private func endDragging(scale: GanttTimeScale, totalWidth: CGFloat) {
        guard let task = draggingTask,
              let finalStart = dragPreviewStart,
              let finalEnd = dragPreviewEnd else {
            resetDragState()
            return
        }

        onTaskDateChanged?(task, finalStart, finalEnd)
        resetDragState()
    }

    private func resetDragState() {
        self.draggingTask = nil
        self.dragMode = .none
        self.dragPreviewStart = nil
        self.dragPreviewEnd = nil
    }

    private func barColor(for item: GanttChartItem) -> LinearGradient {
        if item.isCompleted {
            return LinearGradient(colors: [Color.green.opacity(0.9), Color.green], startPoint: .leading, endPoint: .trailing)
        } else if item.isSubtask {
            return LinearGradient(colors: [Color.purple.opacity(0.8), Color.purple], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [Color.blue.opacity(0.85), Color.blue], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
