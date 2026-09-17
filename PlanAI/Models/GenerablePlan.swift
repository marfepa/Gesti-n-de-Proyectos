import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Representa una subtarea accionable y detallada generada por FoundationModels.
@available(macOS 26.0, *)
@Generable(description: "Subtarea accionable dentro de una fase, con título descriptivo, horas estimadas y descripción detallada de qué hacer")
public struct AISubtaskDetail: Sendable {
    @Guide(description: "Título específico y accionable de la subtarea. No uses títulos genéricos como 'Preparación'. Describe qué se hace concretamente, por ejemplo: 'Crear esquema de base de datos con tablas de usuarios y permisos'")
    public var title: String

    @Guide(description: "Horas estimadas de trabajo efectivo para completar esta subtarea (mínimo 0.5 horas)", .range(0.5...160.0))
    public var estimatedHours: Double

    @Guide(description: "Descripción detallada paso a paso de qué hacer en esta subtarea: herramientas, técnicas, entregables específicos y criterios de finalización")
    public var notes: String

    public init(title: String, estimatedHours: Double, notes: String) {
        self.title = title
        self.estimatedHours = max(0.5, estimatedHours)
        self.notes = notes
    }
}

/// Representa el plan tipado para Guided Generation de Apple Intelligence en macOS 26+.
@available(macOS 26.0, *)
@Generable(description: "Plan estructurado de descomposición de un proyecto en etapas de trabajo lógicas y secuenciales")
public struct AITaskPlan: Sendable {
    @Guide(description: "Lista ordenada y cronológica de fases de trabajo necesarias para completar el proyecto")
    public var subtasks: [AISubtaskPlan]

    public init(subtasks: [AISubtaskPlan] = []) {
        self.subtasks = subtasks
    }
}

/// Representa la fase/tarea principal generada por FoundationModels.
@available(macOS 26.0, *)
@Generable(description: "Fase de trabajo con título, horas estimadas de trabajo efectivo, notas y desglose de subtareas específicas")
public struct AISubtaskPlan: Sendable {
    @Guide(description: "Título conciso, profesional y accionable de la fase")
    public var title: String

    @Guide(description: "Horas estimadas de trabajo efectivo para completar esta fase (mínimo 0.5 horas)", .range(0.5...720.0))
    public var estimatedHours: Double

    @Guide(description: "Breve justificación de por qué es necesaria esta fase y cuál es su entregable")
    public var notes: String

    @Guide(description: "Lista de subtareas concretas y accionables que componen esta fase")
    public var subtasks: [AISubtaskDetail]

    public init(title: String, estimatedHours: Double, notes: String, subtasks: [AISubtaskDetail] = []) {
        self.title = title
        self.estimatedHours = max(0.5, estimatedHours)
        self.notes = notes
        self.subtasks = subtasks
    }
}
#endif

/// Detalle de subtarea desacoplado de FoundationModels para modelos y tests.
public struct SubtaskDetailPlan: Sendable, Codable, Equatable {
    public var title: String
    public var estimatedHours: Double
    public var notes: String

    public init(title: String, estimatedHours: Double, notes: String = "") {
        self.title = title
        self.estimatedHours = max(0.25, estimatedHours)
        self.notes = notes
    }
}

/// Estructura de fase/tarea desacoplada, compatible con todas las versiones de macOS y persistencia.
public struct SubtaskPlan: Sendable, Codable, Equatable {
    public var title: String
    public var estimatedDays: Int
    public var estimatedHours: Double
    public var notes: String
    public var subtaskDetails: [SubtaskDetailPlan]

    public init(
        title: String,
        estimatedDays: Int? = nil,
        estimatedHours: Double? = nil,
        notes: String = "",
        subtaskDetails: [SubtaskDetailPlan] = []
    ) {
        self.title = title
        let resolvedHours = estimatedHours ?? Double(max(1, estimatedDays ?? 1) * 4)
        let resolvedDays = estimatedDays ?? max(1, Int(ceil(resolvedHours / 4.0)))
        self.estimatedDays = max(1, resolvedDays)
        self.estimatedHours = max(0.5, resolvedHours)
        self.notes = notes
        self.subtaskDetails = subtaskDetails
    }
}

public struct TaskPlan: Sendable, Codable, Equatable {
    public var subtasks: [SubtaskPlan]

    public init(subtasks: [SubtaskPlan] = []) {
        self.subtasks = subtasks
    }
}
