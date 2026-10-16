import Foundation
import UserNotifications

/// Servicio de notificaciones locales nativas de macOS para alertas ("Nudges") de tareas con horario fijo.
@MainActor
public final class NotificationService {
    public static let shared = NotificationService()

    public var isAuthorized: Bool = false

    public init() {}

    /// Verifica si el proceso actual se ejecuta dentro de un bundle de aplicación real (evita crashes en `swift test`).
    private var canUseNotificationCenter: Bool {
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else {
            return false
        }
        return Bundle.main.bundleURL.pathExtension == "app"
    }

    public func requestAuthorizationIfNeeded() async -> Bool {
        guard canUseNotificationCenter else { return false }
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            self.isAuthorized = granted
            return granted
        } catch {
            return false
        }
    }

    /// Programa una alerta local para una tarea en su fecha y minuto de inicio (menos `alertOffsetMinutes`).
    public func scheduleNotification(for task: ProjectTask, calendar: Calendar = .current) async {
        guard canUseNotificationCenter else { return }
        guard task.hasFixedTime,
              !task.isCompleted,
              let startMinute = task.fixedStartMinute,
              let offset = task.alertOffsetMinutes else {
            cancelNotification(for: task.id)
            return
        }

        if !isAuthorized {
            let ok = await requestAuthorizationIfNeeded()
            guard ok else { return }
        }

        let baseDate = calendar.startOfDay(for: task.scheduledDate ?? task.startDate)
        let triggerMinute = max(0, startMinute - offset)
        guard let fireDate = calendar.date(byAdding: .minute, value: triggerMinute, to: baseDate),
              fireDate > Date() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = task.title
        if offset == 0 {
            content.body = String(localized: "Es hora de comenzar tu bloque en PlanAI.")
        } else {
            content.body = "Comienza en \(offset) min (\(WorkSlot.formatTime(minute: startMinute)))."
        }
        content.sound = .default

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "planai.task.\(task.id.uuidString)",
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    public func cancelNotification(for taskId: UUID) {
        guard canUseNotificationCenter else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["planai.task.\(taskId.uuidString)"]
        )
    }
}
