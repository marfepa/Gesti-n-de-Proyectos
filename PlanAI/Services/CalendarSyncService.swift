import Foundation
import EventKit

/// Servicio opcional de sincronización con Apple Calendar (EventKit) para mostrar eventos del calendario
/// en el Timeline de Structured y descontar esos huecos de los WorkSlots disponibles.
@Observable
@MainActor
public final class CalendarSyncService {
    public static let shared = CalendarSyncService()

    public var isAuthorized: Bool = false
    public var externalEvents: [ScheduledItem] = []
    public var statusMessage: String?

    private let eventStore = EKEventStore()

    public init() {
        checkCurrentAuthorization()
    }

    public func checkCurrentAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (status == .fullAccess)
    }

    public func requestAccessAndFetch(around referenceDate: Date) async -> Bool {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            self.isAuthorized = granted
            if granted {
                fetchEvents(around: referenceDate)
                statusMessage = nil
            } else {
                statusMessage = String(localized: "Permiso de Calendario denegado en Ajustes del Sistema.")
            }
            return granted
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    public func fetchEvents(around referenceDate: Date, weeks: Int = 4, calendar: Calendar = .current) {
        checkCurrentAuthorization()
        guard isAuthorized else {
            externalEvents = []
            return
        }

        let startWindow = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        let endWindow = calendar.date(byAdding: .day, value: weeks * 7, to: startWindow) ?? referenceDate

        let predicate = eventStore.predicateForEvents(withStart: startWindow, end: endWindow, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)

        var mapped: [ScheduledItem] = []
        for ev in ekEvents where !ev.isAllDay {
            let dayStart = calendar.startOfDay(for: ev.startDate)
            let startHour = calendar.component(.hour, from: ev.startDate)
            let startMin = calendar.component(.minute, from: ev.startDate)
            let endHour = calendar.component(.hour, from: ev.endDate)
            let endMin = calendar.component(.minute, from: ev.endDate)

            let sTotal = startHour * 60 + startMin
            let eTotal = max(sTotal + 15, endHour * 60 + endMin)
            let hours = Double(eTotal - sTotal) / 60.0

            mapped.append(
                ScheduledItem(
                    id: UUID(),
                    taskId: UUID(),
                    projectId: nil,
                    subtaskId: nil,
                    taskTitle: ev.title ?? String(localized: "Evento de Calendario"),
                    subtaskTitle: ev.calendar.title,
                    taskNotes: ev.notes ?? "",
                    subtaskNotes: ev.location,
                    projectName: ev.calendar.title,
                    projectPriority: .alta,
                    date: dayStart,
                    startMinute: sTotal,
                    endMinute: eTotal,
                    allocatedHours: hours,
                    isCompleted: ev.endDate < Date(),
                    iconName: "calendar",
                    colorToken: "nightNavy",
                    subtaskItems: [],
                    isExternalCalendarEvent: true
                )
            )
        }

        self.externalEvents = mapped
    }
}
