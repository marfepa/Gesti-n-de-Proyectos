import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Representa el plan tipado para Guided Generation de Apple Intelligence en macOS 26+.
@available(macOS 26.0, *)
@Generable(description: "Plan estructurado de descomposición de un proyecto en etapas de trabajo lógicas y secuenciales")
public struct AITaskPlan: Sendable {
    @Guide(description: "Lista ordenada y cronológica de subtareas necesarias para completar el proyecto")
    public var subtasks: [AISubtaskPlan]

    public init(subtasks: [AISubtaskPlan] = []) {
        self.subtasks = subtasks
    }
}

/// Representa la subtarea individual generada por FoundationModels.
@available(macOS 26.0, *)
@Generable(description: "Subtarea individual con título, días estimados de trabajo y justificación técnica")
public struct AISubtaskPlan: Sendable {
    @Guide(description: "Título conciso, profesional y accionable de la tarea")
    public var title: String

    @Guide(description: "Estimación de días laborables necesarios para completarla (mínimo 1 día)", .range(1...90))
    public var estimatedDays: Int

    @Guide(description: "Breve justificación de por qué es necesaria esta fase y qué entrega")
    public var notes: String

    public init(title: String, estimatedDays: Int, notes: String) {
        self.title = title
        self.estimatedDays = max(1, estimatedDays)
        self.notes = notes
    }
}
#endif

/// Estructura de dominio desacoplada, compatible con todas las versiones de macOS y persistencia.
public struct SubtaskPlan: Sendable, Codable, Equatable {
    public var title: String
    public var estimatedDays: Int
    public var notes: String

    public init(title: String, estimatedDays: Int, notes: String) {
        self.title = title
        self.estimatedDays = max(1, estimatedDays)
        self.notes = notes
    }
}

public struct TaskPlan: Sendable, Codable, Equatable {
    public var subtasks: [SubtaskPlan]

    public init(subtasks: [SubtaskPlan] = []) {
        self.subtasks = subtasks
    }
}
