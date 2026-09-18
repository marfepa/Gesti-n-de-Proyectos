import Foundation
import SwiftUI
import Speech
import AVFoundation

// MARK: - Public Types

/// Fases del ciclo de vida de grabación y transcripción.
public enum RecordingPhase: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case completed
    case error(String)

    public var isRecording: Bool { self == .recording }
    public var isTranscribing: Bool { self == .transcribing }
}

/// Alias de compatibilidad con código existente que referenciara TranscriptionPhase.
public typealias TranscriptionPhase = RecordingPhase

/// Opción de idioma seleccionable para el reconocedor de voz.
public struct TranscriptionLocaleOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let locale: Locale

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.locale = Locale(identifier: id)
    }

    /// Idiomas recomendados disponibles en macOS.
    public static let recommendedLocales: [TranscriptionLocaleOption] = [
        .init(id: "es-ES", displayName: "Español (España)"),
        .init(id: "es-MX", displayName: "Español (México)"),
        .init(id: "es-US", displayName: "Español (EE.UU.)"),
        .init(id: "en-US", displayName: "English (US)"),
        .init(id: "en-GB", displayName: "English (UK)"),
        .init(id: "fr-FR", displayName: "Français"),
        .init(id: "de-DE", displayName: "Deutsch"),
        .init(id: "it-IT", displayName: "Italiano"),
        .init(id: "pt-BR", displayName: "Português (BR)"),
    ]
}

// MARK: - Recorder Delegate Helper

/// Delegado de AVAudioRecorder aislado del hilo principal para evitar problemas de concurrencia.
private final class AudioRecorderDelegate: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    var onFinish: @Sendable (Bool) -> Void = { _ in }
    var onEncodeError: @Sendable (Error?) -> Void = { _ in }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        onFinish(flag)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        onEncodeError(error)
    }
}

// MARK: - AudioTranscriptionService

/// Servicio observable que orquesta la grabación de voz y su transcripción offline usando
/// AVAudioRecorder (WAV 16 kHz mono) + SFSpeechURLRecognitionRequest.
///
/// Diseñado para macOS 14+ y compatible con macOS 27 beta. No depende de AVAudioEngine ni
/// de SpeechTranscriber (API aún inestable en beta).
@Observable
@MainActor
public final class AudioTranscriptionService {

    // MARK: Public State

    public var phase: RecordingPhase = .idle
    public var recordingDuration: TimeInterval = 0
    public var transcriptionProgress: Double = 0
    public var transcribedText: String = ""
    public var errorMessage: String?

    public var isRecording: Bool { phase == .recording }
    public var isTranscribing: Bool { phase == .transcribing }

    public var selectedLocaleOption: TranscriptionLocaleOption = TranscriptionLocaleOption.recommendedLocales[0]
    public var availableLocales: [TranscriptionLocaleOption] = TranscriptionLocaleOption.recommendedLocales

    // MARK: Private

    private var audioRecorder: AVAudioRecorder?
    private var recorderDelegate: AudioRecorderDelegate?
    private var recordedFileURL: URL?
    private var durationTimer: Timer?
    private var currentRecognitionTask: SFSpeechRecognitionTask?

    public init() {
        filterSupportedLocales()
    }

    // MARK: - Permissions

    /// Solicita permisos de Reconocimiento de Voz y Micrófono si aún no se han concedido.
    /// Retorna `true` si ambos permisos están disponibles.
    public func requestPermissionsIfNeeded() async -> Bool {
        guard await requestSpeechPermission() else {
            errorMessage = "PlanAI necesita permiso de Reconocimiento de Voz.\n" +
                           "Actívalo en Ajustes del Sistema › Privacidad › Reconocimiento de voz."
            return false
        }
        guard await requestMicrophonePermission() else {
            errorMessage = "PlanAI necesita permiso del Micrófono.\n" +
                           "Actívalo en Ajustes del Sistema › Privacidad › Micrófono."
            return false
        }
        return true
    }

    private func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .undetermined:
                return await AVAudioApplication.requestRecordPermission()
            default:
                return false
            }
        } else {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                return true
            case .notDetermined:
                return await withCheckedContinuation { cont in
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        cont.resume(returning: granted)
                    }
                }
            default:
                return false
            }
        }
    }

    // MARK: - Recording

    /// Inicia la grabación de audio con AVAudioRecorder (WAV 16 kHz mono).
    /// Estrategia defensiva: sin AVAudioEngine, sin taps, sin graph de audio.
    public func startRecording() async {
        guard phase == .idle else { return }

        // 1. Permisos
        guard await requestPermissionsIfNeeded() else {
            phase = .error(errorMessage ?? "Sin permisos")
            return
        }

        // 2. Limpiar estado previo
        cleanupTempFile()
        errorMessage = nil
        transcribedText = ""
        transcriptionProgress = 0

        // 3. URL temporal
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("planai_rec_\(UUID().uuidString).wav")
        recordedFileURL = url

        // 4. Formato: 16 kHz mono 16-bit PCM — óptimo para SFSpeechRecognizer, sin overhead de codificación
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)

            // 5. Delegate nonisolated para evitar re-entrancy en MainActor
            let delegate = AudioRecorderDelegate()
            delegate.onFinish = { [weak self] success in
                guard !success else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Solo reportar si no estamos ya en transcripción o completado
                    if self.phase != .transcribing && self.phase != .completed {
                        self.errorMessage = "La grabación finalizó inesperadamente. Inténtalo de nuevo."
                        self.phase = .error("Grabación fallida")
                    }
                }
            }
            delegate.onEncodeError = { [weak self] error in
                Task { @MainActor [weak self] in
                    let msg = error?.localizedDescription ?? "Error de codificación de audio."
                    self?.errorMessage = msg
                    self?.phase = .error(msg)
                }
            }
            recorder.delegate = delegate
            recorderDelegate = delegate  // Retener el delegado

            // 6. Preparar y arrancar
            recorder.prepareToRecord()
            let started = recorder.record()

            guard started else {
                throw NSError(
                    domain: "PlanAI.Audio", code: 10,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No se pudo iniciar la grabación. Comprueba que el micrófono no esté siendo usado por otra aplicación."]
                )
            }

            audioRecorder = recorder
            phase = .recording
            recordingDuration = 0
            startDurationTimer()

        } catch {
            cleanupTempFile()
            errorMessage = error.localizedDescription
            phase = .error(error.localizedDescription)
        }
    }

    /// Detiene la grabación y lanza la transcripción automáticamente.
    public func stopRecordingAndTranscribe() {
        guard phase == .recording else { return }

        stopDurationTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        recorderDelegate = nil

        Task {
            await performTranscription()
        }
    }

    // MARK: - Transcription

    private func performTranscription() async {
        guard let url = recordedFileURL, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "No se encontró el archivo de audio grabado."
            phase = .error("Archivo no encontrado.")
            return
        }

        phase = .transcribing
        transcriptionProgress = 0.05

        let locale = selectedLocaleOption.locale

        do {
            let text = try await transcribeAudioFile(url: url, locale: locale)
            transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            transcriptionProgress = 1.0
            phase = .completed
            cleanupTempFile()
        } catch is CancellationError {
            phase = .idle
            errorMessage = nil
            cleanupTempFile()
        } catch {
            errorMessage = "No se pudo transcribir: \(error.localizedDescription)"
            phase = .error(error.localizedDescription)
            cleanupTempFile()
        }
    }

    /// Intenta transcripción on-device; si el modelo no está disponible, reintenta via red.
    private func transcribeAudioFile(url: URL, locale: Locale) async throws -> String {
        do {
            return try await recognizeFile(url: url, locale: locale, onDevice: true)
        } catch let err as NSError
            where err.domain == "kAFAssistantErrorDomain"
               || err.code == 203
               || err.code == 201 {
            // Modelo on-device no disponible → reintentar via red
            return try await recognizeFile(url: url, locale: locale, onDevice: false)
        }
    }

    private func recognizeFile(url: URL, locale: Locale, onDevice: Bool) async throws -> String {
        // Obtener reconocedor; fallback a es-ES si el locale pedido no existe
        guard let recognizer = SFSpeechRecognizer(locale: locale)
                             ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES")),
              recognizer.isAvailable else {
            throw NSError(
                domain: "PlanAI.Audio", code: 20,
                userInfo: [NSLocalizedDescriptionKey:
                    "El reconocedor de voz no está disponible para «\(locale.identifier)». " +
                    "Asegúrate de tener el idioma instalado en tu Mac."]
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = onDevice
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { cont in
            var resumed = false

            // Captura débil explícita para los closures internos
            let weakSelf = self as AudioTranscriptionService?

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(throwing: error)
                    return
                }

                guard let result else { return }

                if result.isFinal {
                    guard !resumed else { return }
                    resumed = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                    return
                }

                // Progreso incremental visible mientras llegan resultados parciales
                Task { @MainActor in
                    guard let svc = weakSelf, svc.transcriptionProgress < 0.88 else { return }
                    svc.transcriptionProgress = min(0.88, svc.transcriptionProgress + 0.12)
                }
            }

            self.currentRecognitionTask = task

            // Timeout de seguridad: 120 segundos
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard !resumed else { return }
                resumed = true
                task.finish()
                cont.resume(returning: "")
            }
        }
    }

    // MARK: - Cancel / Reset

    /// Cancela cualquier grabación o transcripción en curso y resetea el estado.
    public func cancel() {
        stopDurationTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        recorderDelegate = nil
        currentRecognitionTask?.cancel()
        currentRecognitionTask = nil
        cleanupTempFile()
        phase = .idle
        transcriptionProgress = 0
        errorMessage = nil
    }

    /// Resetea el servicio a idle tras haber consumido el texto transcrito.
    public func resetAfterCompletion() {
        guard phase == .completed else { return }
        transcribedText = ""
        transcriptionProgress = 0
        phase = .idle
    }

    // MARK: - Helpers

    private func filterSupportedLocales() {
        let supported = SFSpeechRecognizer.supportedLocales()
        let filtered = TranscriptionLocaleOption.recommendedLocales.filter { supported.contains($0.locale) }
        if !filtered.isEmpty {
            availableLocales = filtered
            if !filtered.contains(where: { $0.id == selectedLocaleOption.id }) {
                selectedLocaleOption = filtered[0]
            }
        }
    }

    private func cleanupTempFile() {
        guard let url = recordedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordedFileURL = nil
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordingDuration += 0.1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    public var formattedDuration: String {
        let total = Int(recordingDuration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
