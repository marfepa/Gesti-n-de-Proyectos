import SwiftUI

/// Modal para añadir un nuevo momento disponible (WorkSlot) en días seleccionados.
public struct AddWorkSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let onAdd: ([WorkSlot]) -> Void

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

    public init(onAdd: @escaping ([WorkSlot]) -> Void) {
        self.onAdd = onAdd
    }

    public var body: some View {
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
