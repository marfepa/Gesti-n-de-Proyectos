import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Estado del motor de inteligencia artificial en el dispositivo.
public enum AIModelStatus: Equatable, Sendable {
    case ready
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelDownloading
    case unsupportedOSOrFramework
    case unavailable(String)

    public var isAvailable: Bool {
        self == .ready
    }
}

/// Servicio que monitorea la disponibilidad de Apple Intelligence y el modelo FoundationModels.
@Observable
public final class AIAvailabilityService {
    public var status: AIModelStatus = .unsupportedOSOrFramework
    public var isChecking: Bool = false

    public init() {
        checkAvailability()
    }

    public func checkAvailability() {
        isChecking = true
        defer { isChecking = false }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                self.status = .ready
            case .unavailable(.deviceNotEligible):
                self.status = .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                self.status = .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                self.status = .modelDownloading
            case .unavailable(let reason):
                self.status = .unavailable(String(describing: reason))
            }
        } else {
            self.status = .unsupportedOSOrFramework
        }
        #else
        self.status = .unsupportedOSOrFramework
        #endif
    }

    /// Mensaje descriptivo del estado según el idioma de la aplicación.
    public var localizedDescription: String {
        switch status {
        case .ready:
            return String(localized: "Apple Intelligence está activo y listo para procesar en el Neural Engine.")
        case .deviceNotEligible:
            return String(localized: "Este dispositivo no es compatible con Apple Intelligence (requiere Apple Silicon M1 o posterior).")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Apple Intelligence está desactivado. Actívalo en Ajustes del Sistema > Apple Intelligence.")
        case .modelDownloading:
            return String(localized: "El modelo de lenguaje del sistema se está descargando o preparando. Vuelve a intentarlo en unos minutos.")
        case .unsupportedOSOrFramework:
            return String(localized: "El framework FoundationModels requiere macOS 26.0 o superior.")
        case .unavailable(let reason):
            return String(localized: "Modelo no disponible: \(reason)")
        }
    }
}
