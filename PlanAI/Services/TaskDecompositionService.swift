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
                Eres un gestor de proyectos senior con 20 años de experiencia estimando software y proyectos creativos.

                REGLAS CRÍTICAS DE ESTIMACIÓN:
                - Estima en HORAS de trabajo efectivo, no en días completos.
                - Una reunión de kickoff típica dura 1-2 horas, no un día.
                - Configurar un entorno de desarrollo toma 2-4 horas, no días.
                - Escribir un documento de requisitos de 2-3 páginas toma 3-6 horas.
                - Un diseño de UI sencillo (5-10 pantallas) toma 8-16 horas.
                - Implementar un CRUD básico toma 4-8 horas.
                - Implementar autenticación con un framework existente toma 4-8 horas.
                - Escribir tests unitarios para un módulo pequeño toma 2-4 horas.
                - Una revisión de código detallada toma 1-3 horas.
                - NO infles estimaciones "por si acaso". Sé realista y ajustado.
                - Si una fase entera dura menos de 4 horas, NO la dividas en más de 2 subtareas.
                - Tareas muy cortas (< 1 hora) pueden no necesitar subtareas.

                REGLAS PARA SUBTAREAS:
                - Cada fase principal DEBE tener subtareas específicas y accionables.
                - Los títulos de subtareas deben describir QUÉ se hace concretamente, nunca usar genéricos como "Preparación" o "Revisión general".
                - La descripción de cada subtarea debe explicar paso a paso qué hacer, qué herramientas usar y cuál es el entregable.
                - Ejemplo MALO de subtarea: "Preparación del diseño" (genérico, sin detalle)
                - Ejemplo BUENO de subtarea: "Crear wireframes de flujo de login y registro en Figma con 3 estados: vacío, con datos, error" (específico, accionable)

                Desglosa el proyecto en fases lógicas secuenciales, cada una con subtareas detalladas.
                """

            let session = LanguageModelSession(instructions: instructions)

            let prompt = """
                Desglosa este proyecto en fases de trabajo secuenciales con subtareas detalladas.
                Estima las horas de trabajo efectivo de manera realista y ajustada.

                Descripción del proyecto:
                \(trimmed)
                """

            do {
                let response = try await session.respond(to: prompt, generating: AITaskPlan.self)
                let subtasks = response.content.subtasks.map { phase in
                    SubtaskPlan(
                        title: phase.title,
                        estimatedHours: phase.estimatedHours,
                        notes: phase.notes,
                        subtaskDetails: phase.subtasks.map {
                            SubtaskDetailPlan(title: $0.title, estimatedHours: $0.estimatedHours, notes: $0.notes)
                        }
                    )
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

    /// Convierte el plan tipado devuelto por la IA o fallback en payloads con fechas deterministas calculadas mediante Calendar.
    public func buildTaskPayloads(
        from subtasks: [SubtaskPlan],
        startingAt startDate: Date,
        targetEndDate: Date? = nil,
        hoursPerDay: Double = 4.0,
        calendar: Calendar = .current
    ) -> [GeneratedTaskPayload] {
        var currentStart = calendar.startOfDay(for: startDate)
        var results: [GeneratedTaskPayload] = []

        let effectiveHoursPerDay = max(1.0, hoursPerDay)

        // Si se especificó una fecha objetivo de fin y las duraciones en horas la excederían,
        // calcular factor de compresión sobre las horas totales
        var compressionRatio: Double = 1.0
        let totalRawHours = subtasks.reduce(0.0) { sum, item in
            let itemHours = item.estimatedHours > 0 ? item.estimatedHours : Double(item.estimatedDays * 4)
            return sum + max(0.5, itemHours)
        }
        let totalRawDays = max(1, Int(ceil(totalRawHours / effectiveHoursPerDay)))

        if let target = targetEndDate {
            let normalizedTarget = calendar.startOfDay(for: target)
            let comps = calendar.dateComponents([.day], from: currentStart, to: normalizedTarget)
            let availableDays = max(1, comps.day ?? totalRawDays)
            if totalRawDays > availableDays {
                compressionRatio = Double(availableDays) / Double(totalRawDays)
            }
        }

        for (index, item) in subtasks.enumerated() {
            let baseHours = item.estimatedHours > 0 ? item.estimatedHours : Double(item.estimatedDays * 4)
            let compressedHours = max(0.5, baseHours * compressionRatio)
            let calculatedDays = max(1, Int(ceil(compressedHours / effectiveHoursPerDay)))
            let taskEnd = calendar.date(byAdding: .day, value: calculatedDays, to: currentStart) ?? currentStart

            // Subtareas: preferir las generadas por el LLM o fallback
            var generatedSubtasks: [(title: String, hours: Double, notes: String)] = []
            if !item.subtaskDetails.isEmpty {
                generatedSubtasks = item.subtaskDetails.map {
                    (title: $0.title, hours: max(0.5, $0.estimatedHours * compressionRatio), notes: $0.notes)
                }
            } else if calculatedDays >= 2 || compressedHours >= 6.0 {
                // Si no hay subtareas provistas y la tarea es grande, generamos subtareas heurísticas
                let step1Hours = max(0.5, round((compressedHours * 0.25) * 2) / 2)
                let step2Hours = max(0.5, round((compressedHours * 0.50) * 2) / 2)
                let step3Hours = max(0.5, max(0.5, compressedHours - step1Hours - step2Hours))
                generatedSubtasks = [
                    (title: "Especificación técnica y preparación: \(item.title)", hours: step1Hours, notes: "Definir requisitos y dependencias iniciales"),
                    (title: "Implementación principal", hours: step2Hours, notes: "Desarrollo de las piezas clave"),
                    (title: "Verificación y pruebas", hours: step3Hours, notes: "Revisión de calidad y validación")
                ]
            }

            let payload = GeneratedTaskPayload(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: item.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: currentStart,
                endDate: taskEnd,
                estimatedDays: calculatedDays,
                estimatedHours: compressedHours,
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
                let hours = Double((idx + 1) * 4)
                let subDetails = [
                    SubtaskDetailPlan(title: "Kickoff y alcance de \(cleanTitle)", estimatedHours: max(0.5, hours * 0.3), notes: "Alineación de objetivos y entregables"),
                    SubtaskDetailPlan(title: "Ejecución técnica de \(cleanTitle)", estimatedHours: max(0.5, hours * 0.7), notes: "Desarrollo de la fase y entregables")
                ]
                subtasks.append(SubtaskPlan(
                    title: cleanTitle,
                    estimatedHours: hours,
                    notes: "Fase generada automáticamente a partir del plan manual.",
                    subtaskDetails: subDetails
                ))
            }
        } else {
            // Fases estándar calibradas en horas realistas con subtareas accionables
            subtasks = [
                SubtaskPlan(
                    title: "Análisis de Requisitos y Alcance",
                    estimatedHours: 6.0,
                    notes: "Definición concisa de especificaciones técnicas y criterios de aceptación.",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Entrevistas de requerimientos y casos de uso", estimatedHours: 3.0, notes: "Identificar requerimientos funcionales críticos y restricciones."),
                        SubtaskDetailPlan(title: "Documentación de especificación técnica", estimatedHours: 3.0, notes: "Redactar documento de 2-3 páginas con criterios de aceptación.")
                    ]
                ),
                SubtaskPlan(
                    title: "Diseño y Arquitectura",
                    estimatedHours: 8.0,
                    notes: "Estructuración de componentes, modelos de datos y wireframes.",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Diseño de wireframes en Figma", estimatedHours: 4.0, notes: "Crear flujos visuales principales con estados vacío, activo y error."),
                        SubtaskDetailPlan(title: "Definición del modelo de datos y contratos de API", estimatedHours: 4.0, notes: "Estructurar esquemas SwiftData / endpoints.")
                    ]
                ),
                SubtaskPlan(
                    title: "Implementación Core",
                    estimatedHours: 16.0,
                    notes: "Desarrollo de las funcionalidades críticas del proyecto.",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Configuración de servicios base e inyección", estimatedHours: 4.0, notes: "Estructurar infraestructura y modelos persistentes."),
                        SubtaskDetailPlan(title: "Desarrollo de pantallas principales y vistas SwiftUI", estimatedHours: 8.0, notes: "Construcción interactiva de los componentes de UI."),
                        SubtaskDetailPlan(title: "Integración de lógica de negocio y persistencia", estimatedHours: 4.0, notes: "Conectar viewmodels con modelos y validaciones.")
                    ]
                ),
                SubtaskPlan(
                    title: "Pruebas y Verificación",
                    estimatedHours: 6.0,
                    notes: "Validación de calidad, cobertura de pruebas unitarias y corrección de errores.",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Creación de suite de tests unitarios", estimatedHours: 3.0, notes: "Cobertura de casos límite y regresiones críticas."),
                        SubtaskDetailPlan(title: "Pruebas de interfaz y pulido de casos extremos", estimatedHours: 3.0, notes: "Validar rendimiento, accesibilidad y estados de error.")
                    ]
                ),
                SubtaskPlan(
                    title: "Despliegue y Cierre",
                    estimatedHours: 4.0,
                    notes: "Generación de artefactos de entrega y documentación final.",
                    subtaskDetails: [
                        SubtaskDetailPlan(title: "Configuración de compilación y empaquetado", estimatedHours: 2.0, notes: "Verificar esquema de release y firmas."),
                        SubtaskDetailPlan(title: "Documentación de entrega y guía de usuario", estimatedHours: 2.0, notes: "Manual de usuario y changelog.")
                    ]
                )
            ]
        }

        return buildTaskPayloads(from: subtasks, startingAt: startDate, targetEndDate: targetEndDate, calendar: calendar)
    }

    /// Descompone una tarea grande en un conjunto de subtareas accionables y más pequeñas (heurística).
    public func decomposeTaskIntoSubtasks(
        taskTitle: String,
        taskNotes: String = "",
        estimatedHours: Double
    ) -> [(title: String, hours: Double, notes: String)] {
        let cleanTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalHours = max(1.0, estimatedHours)

        let step1Hours = max(0.5, round((totalHours * 0.25) * 2) / 2)
        let step2Hours = max(0.5, round((totalHours * 0.50) * 2) / 2)
        let step3Hours = max(0.5, max(0.5, totalHours - step1Hours - step2Hours))

        return [
            (title: "Definición y especificación técnica: \(cleanTitle)", hours: step1Hours, notes: "Revisar requerimientos y alcance detallado"),
            (title: "Desarrollo e implementación principal", hours: step2Hours, notes: "Construcción técnica de la solución"),
            (title: "Pruebas, verificación y ajustes", hours: step3Hours, notes: "Validar funcionamiento y pulir detalles")
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
    public var estimatedHours: Double
    public var sortOrder: Int
    public var subtasks: [(title: String, hours: Double, notes: String)]

    public init(
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date,
        estimatedDays: Int,
        estimatedHours: Double? = nil,
        sortOrder: Int,
        subtasks: [(title: String, hours: Double, notes: String)] = []
    ) {
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.estimatedDays = max(1, estimatedDays)
        self.estimatedHours = estimatedHours ?? Double(max(1, estimatedDays) * 4)
        self.sortOrder = sortOrder
        self.subtasks = subtasks
    }
}
