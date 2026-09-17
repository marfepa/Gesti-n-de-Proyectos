import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Errores específicos del servicio de descomposición con IA.
public enum DecompositionError: LocalizedError, Sendable {
    case modelUnavailable(String)
    case contextWindowExceeded
    case guardrailViolation
    case emptyInput
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return String(localized: "El modelo de lenguaje on-device no está disponible: \(reason)")
        case .contextWindowExceeded:
            return String(localized: "La descripción del proyecto es demasiado larga para la ventana de contexto del modelo. Intenta resumirla a 1-3 párrafos.")
        case .guardrailViolation:
            return String(localized: "La solicitud activó las políticas de seguridad del sistema. Reformula la descripción del proyecto.")
        case .emptyInput:
            return String(localized: "Por favor proporciona una descripción válida para descomponer el proyecto.")
        case .generationFailed(let msg):
            return String(localized: "Fallo en la generación guiada: \(msg)")
        }
    }
}

/// Servicio que orquesta la llamada a FoundationModels y el cálculo determinista de cronogramas.
public final class TaskDecompositionService: Sendable {

    public init() {}

    /// Descompone una descripción de proyecto en un conjunto estructurado de tareas secuenciales con fechas calculadas.
    public func decompose(
        projectDescription: String,
        startDate: Date,
        targetEndDate: Date? = nil,
        calendar: Calendar = .current
    ) async throws -> [GeneratedTaskPayload] {
        let trimmed = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DecompositionError.emptyInput
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available else {
                throw DecompositionError.modelUnavailable(String(describing: model.availability))
            }

            let instructions = """
                Eres un gestor de proyectos técnico de élite. Tu misión es desglosar la descripción
                de cualquier proyecto en fases secuenciales lógicas, viables y ordenadas cronológicamente,
                estimando la duración en días laborables de cada una y explicando brevemente el entregable.
                """

            let session = LanguageModelSession(instructions: instructions)

            let prompt = """
                Desglosa este proyecto en pasos lógicos de trabajo:
                \(trimmed)
                """

            do {
                let response = try await session.respond(to: prompt, generating: AITaskPlan.self)
                let subtasks = response.content.subtasks.map {
                    SubtaskPlan(title: $0.title, estimatedDays: $0.estimatedDays, notes: $0.notes)
                }
                return buildTaskPayloads(from: subtasks, startingAt: startDate, targetEndDate: targetEndDate, calendar: calendar)
            } catch {
                let errorString = String(describing: error)
                if errorString.contains("context") || errorString.contains("exceeded") {
                    throw DecompositionError.contextWindowExceeded
                } else if errorString.contains("guardrail") || errorString.contains("safety") {
                    throw DecompositionError.guardrailViolation
                } else {
                    throw DecompositionError.generationFailed(error.localizedDescription)
                }
            }
        } else {
            return generateHeuristicPlan(from: trimmed, startDate: startDate, targetEndDate: targetEndDate, calendar: calendar)
        }
        #else
        // Fallback heurístico para entornos sin FoundationModels
        return generateHeuristicPlan(from: trimmed, startDate: startDate, targetEndDate: targetEndDate, calendar: calendar)
        #endif
    }

    /// Convierte el plan tipado devuelto por la IA en payloads con fechas deterministas calculadas mediante Calendar.
    public func buildTaskPayloads(
        from subtasks: [SubtaskPlan],
        startingAt startDate: Date,
        targetEndDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [GeneratedTaskPayload] {
        var currentStart = calendar.startOfDay(for: startDate)
        var results: [GeneratedTaskPayload] = []

        // Si se especificó una fecha objetivo de fin y las duraciones la excederían,
        // calcular factor de compresión para encajar en la ventana
        var compressionRatio: Double = 1.0
        let rawTotalDays = subtasks.reduce(0) { $0 + max(1, $1.estimatedDays) }

        if let target = targetEndDate {
            let normalizedTarget = calendar.startOfDay(for: target)
            let comps = calendar.dateComponents([.day], from: currentStart, to: normalizedTarget)
            let availableDays = max(1, comps.day ?? rawTotalDays)
            if rawTotalDays > availableDays {
                compressionRatio = Double(availableDays) / Double(rawTotalDays)
            }
        }

        for (index, item) in subtasks.enumerated() {
            let rawDays = Double(max(1, item.estimatedDays))
            let compressedDays = max(1, Int(round(rawDays * compressionRatio)))
            let taskEnd = calendar.date(byAdding: .day, value: compressedDays, to: currentStart) ?? currentStart

            // Si la tarea es grande (>= 2 días o >= 6 horas), generar subtareas atómicas
            let hours = Double(compressedDays * 4)
            var generatedSubtasks: [(title: String, hours: Double)] = []
            if compressedDays >= 2 || hours >= 6.0 {
                generatedSubtasks = decomposeTaskIntoSubtasks(taskTitle: item.title, taskNotes: item.notes, estimatedHours: hours)
            }

            let payload = GeneratedTaskPayload(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: item.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: currentStart,
                endDate: taskEnd,
                estimatedDays: compressedDays,
                sortOrder: index,
                subtasks: generatedSubtasks
            )
            results.append(payload)

            // La siguiente tarea comienza donde finaliza la anterior
            currentStart = taskEnd
        }

        return results
    }

    /// Generador heurístico de respaldo cuando FoundationModels no está disponible en la máquina.
    public func generateHeuristicPlan(
        from description: String,
        startDate: Date,
        targetEndDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [GeneratedTaskPayload] {
        let lines = description.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var subtasks: [SubtaskPlan] = []

        if lines.count >= 2 {
            for (idx, line) in lines.enumerated() {
                let cleanTitle = line.replacingOccurrences(of: "^[0-9]+[.)-]\\s*", with: "", options: .regularExpression)
                subtasks.append(SubtaskPlan(
                    title: cleanTitle,
                    estimatedDays: (idx + 1) * 2,
                    notes: "Fase generada automáticamente a partir del plan manual."
                ))
            }
        } else {
            // Fases estándar por defecto
            subtasks = [
                SubtaskPlan(title: "Análisis de Requisitos y Alcance", estimatedDays: 3, notes: "Definición de especificaciones técnicas y requerimientos."),
                SubtaskPlan(title: "Diseño y Arquitectura", estimatedDays: 4, notes: "Estructuración de componentes, modelos y flujos."),
                SubtaskPlan(title: "Implementación Core", estimatedDays: 7, notes: "Desarrollo de las funcionalidades críticas del proyecto."),
                SubtaskPlan(title: "Pruebas y Verificación", estimatedDays: 3, notes: "Validación de calidad, corrección de errores y rendimiento."),
                SubtaskPlan(title: "Despliegue y Cierre", estimatedDays: 2, notes: "Puesta en producción y documentación de entrega.")
            ]
        }

        return buildTaskPayloads(from: subtasks, startingAt: startDate, targetEndDate: targetEndDate, calendar: calendar)
    }

    /// Descompone una tarea grande en un conjunto de subtareas accionables y más pequeñas.
    public func decomposeTaskIntoSubtasks(
        taskTitle: String,
        taskNotes: String = "",
        estimatedHours: Double
    ) -> [(title: String, hours: Double)] {
        let cleanTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalHours = max(1.0, estimatedHours)

        // Generar desglose lógico según la naturaleza de la tarea
        let step1Hours = max(0.5, round((totalHours * 0.25) * 2) / 2)
        let step2Hours = max(0.5, round((totalHours * 0.50) * 2) / 2)
        let step3Hours = max(0.5, max(0.5, totalHours - step1Hours - step2Hours))

        return [
            ("Definición y preparación: \(cleanTitle)", step1Hours),
            ("Desarrollo y ejecución principal", step2Hours),
            ("Revisión, pruebas y validación", step3Hours)
        ]
    }
}

/// DTO intermedio para transferir datos generados antes de persistir en SwiftData.
public struct GeneratedTaskPayload: Sendable {
    public var title: String
    public var notes: String
    public var startDate: Date
    public var endDate: Date
    public var estimatedDays: Int
    public var sortOrder: Int
    public var subtasks: [(title: String, hours: Double)]

    public init(
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date,
        estimatedDays: Int,
        sortOrder: Int,
        subtasks: [(title: String, hours: Double)] = []
    ) {
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.estimatedDays = estimatedDays
        self.sortOrder = sortOrder
        self.subtasks = subtasks
    }
}
