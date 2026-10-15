import SwiftUI

public struct DayStripView: View {
    @Binding public var selectedDate: Date
    @Binding public var isSheetExpanded: Bool
    public var scheduledItems: [ScheduledItem]
    public var onOpenAI: () -> Void = {}
    public var onOpenSearch: () -> Void = {}
    public var onOpenSettings: () -> Void = {}

    @State private var showingDatePickerPopover: Bool = false
    @State private var currentWeekStart: Date = DayStripView.mondayOfWeek(containing: Date())

    public init(
        selectedDate: Binding<Date>,
        isSheetExpanded: Binding<Bool> = .constant(true),
        scheduledItems: [ScheduledItem],
        onOpenAI: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self._selectedDate = selectedDate
        self._isSheetExpanded = isSheetExpanded
        self.scheduledItems = scheduledItems
        self.onOpenAI = onOpenAI
        self.onOpenSearch = onOpenSearch
        self.onOpenSettings = onOpenSettings
    }

    private var calendar: Calendar { Calendar.current }

    public static func mondayOfWeek(containing date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let startOfDay = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: startOfDay)
        let daysToMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysToMonday, to: startOfDay) ?? startOfDay
    }

    private var daysInWeek: [Date] {
        (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: currentWeekStart)
        }
    }

    private var monthOnlyString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "MMMM"
        let str = formatter.string(from: selectedDate)
        return str.prefix(1).uppercased() + str.dropFirst()
    }

    private var monthAndDayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "MMMM d,"
        let str = formatter.string(from: selectedDate)
        return str.prefix(1).uppercased() + str.dropFirst()
    }

    private var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: selectedDate)
    }

    public var body: some View {
        VStack(spacing: 12) {
            // 1. Fila Superior: Título dinámico ("Octubre 2026 >" o "Octubre 15, 2026 >") + Utilidades
            ZStack {
                HStack(spacing: 12) {
                    Button {
                        shiftWeek(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Semana anterior")

                    Button {
                        showingDatePickerPopover.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(isSheetExpanded ? monthAndDayString : monthOnlyString)
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            Text(yearString)
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(StructuredTheme.coral)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(StructuredTheme.coral)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingDatePickerPopover) {
                        VStack(spacing: 10) {
                            DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                                .padding()
                            Button(String(localized: "Ir a Hoy")) {
                                selectedDate = calendar.startOfDay(for: Date())
                                showingDatePickerPopover = false
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .buttonStyle(.borderedProminent)
                            .tint(StructuredTheme.coral)
                            .padding(.bottom, 10)
                        }
                        .frame(width: 280)
                    }

                    Button {
                        shiftWeek(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Semana siguiente")
                }

                HStack(spacing: 8) {
                    Spacer()

                    Button(action: onOpenAI) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text("AI")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Descomponer proyecto con Apple Intelligence")

                    Button(action: onOpenSearch) {
                        Image(systemName: isSheetExpanded ? "calendar.day.timeline.left" : "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.65))
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Alternar vista semanal / diaria")

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.65))
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Ajustes de Structured / PlanAI")
                }
            }
            .padding(.horizontal, 24)

            // 2. Fila de los 7 días (Con height: 1 en el espaciador para evitar que Color.clear expanda el HStack)
            HStack(spacing: 0) {
                if !isSheetExpanded {
                    Color.clear.frame(width: 48, height: 1)
                }

                ForEach(daysInWeek, id: \.self) { date in
                    dayColumn(for: date)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .padding(.bottom, isSheetExpanded ? 8 : 2)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            currentWeekStart = Self.mondayOfWeek(containing: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            let weekOfNewDate = Self.mondayOfWeek(containing: newDate)
            if weekOfNewDate != currentWeekStart {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    currentWeekStart = weekOfNewDate
                }
            }
        }
    }

    private func shiftWeek(by weeks: Int) {
        if let newDate = calendar.date(byAdding: .day, value: weeks * 7, to: selectedDate) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedDate = newDate
            }
        }
    }

    @ViewBuilder
    private func dayColumn(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let weekdayLabel = shortWeekday(for: date)
        let dayNum = calendar.component(.day, from: date)
        let itemsForDay = scheduledItems
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.startMinute < $1.startMinute }

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                selectedDate = calendar.startOfDay(for: date)
                isSheetExpanded = true
            }
        } label: {
            VStack(spacing: 5) {
                VStack(spacing: 4) {
                    Text(weekdayLabel)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? StructuredTheme.coral : .secondary)

                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(StructuredTheme.coral)
                                .frame(width: 30, height: 30)
                            Text("\(dayNum)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(dayNum)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? StructuredTheme.coralLight : Color.clear)
                )

                if isSheetExpanded {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(StructuredTheme.coral.opacity(0.85))
                            .frame(width: 11, height: 11)
                            .overlay(
                                Image(systemName: "alarm.fill")
                                    .font(.system(size: 5.5))
                                    .foregroundStyle(.white)
                            )

                        ForEach(itemsForDay.prefix(3)) { item in
                            Circle()
                                .fill(StructuredTheme.coralLight)
                                .frame(width: 11, height: 11)
                                .overlay(
                                    Image(systemName: item.iconName)
                                        .font(.system(size: 5.5, weight: .bold))
                                        .foregroundStyle(StructuredTheme.coral)
                                )
                                .overlay(
                                    Circle().stroke(StructuredTheme.coral.opacity(0.6), lineWidth: 0.8)
                                )
                        }

                        Circle()
                            .fill(StructuredTheme.nightNavy.opacity(0.85))
                            .frame(width: 11, height: 11)
                            .overlay(
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 5.5))
                                    .foregroundStyle(.white)
                            )
                    }
                    .frame(height: 12)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortWeekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEE"
        let str = formatter.string(from: date).replacingOccurrences(of: ".", with: "")
        return str.prefix(1).uppercased() + str.dropFirst()
    }
}
