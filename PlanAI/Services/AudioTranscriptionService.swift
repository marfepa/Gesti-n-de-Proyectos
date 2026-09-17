import Foundation
import SwiftUI
import Speech
import AVFoundation

/// Opción de idioma seleccionable para el motor de transcripción de Apple.
public struct TranscriptionLocaleOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let locale: Locale

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.locale = Locale(identifier: id)
    }

    /// Idiomas recomendados y más comunes disponibles en macOS
    public static let recommendedLocales: [TranscriptionLocaleOption] = [
        TranscriptionLocaleOption(id: "es-ES", displayName: "Español (España)"),
        TranscriptionLocaleOption(id: "es-MX", displayName: "Español (México)"),
        TranscriptionLocaleOption(id: "es-US", displayName: "Español (Estados Unidos)"),
        TranscriptionLocaleOption(id: "en-US", displayName: "English (United States)"),
        TranscriptionLocaleOption(id: "en-GB", displayName: "English (United Kingdom)"),
        TranscriptionLocaleOption(id: "fr-FR", displayName: "Français (France)"),
        TranscriptionLocaleOption(id: "de-DE", displayName: "Deutsch (Deutschland)"),
        TranscriptionLocaleOption(id: "it-IT", displayName: "Italiano (Italia)"),
        TranscriptionLocaleOption(id: "pt-BR", displayName: "Português (Brasil)")
    ]
}

/// Servicio observable que orquesta la captura de audio con AVAudioEngine y la transcripción en vivo con Speech framework.
@Observable
@MainActor
public final class AudioTranscriptionService {
    public var isRecording: Bool = false
    public var recordingDuration: TimeInterval = 0
    public var liveTranscript: String = ""
    public var errorMessage: String?
    public var isAuthorized: Bool = false
    
    public var selectedLocaleOption: TranscriptionLocaleOption = TranscriptionLocaleOption.recommendedLocales[0] {
        didSet {
            setupRecognizer()
        }
    }
    
    public var availableLocales: [TranscriptionLocaleOption] = TranscriptionLocaleOption.recommendedLocales

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var durationTimer: Timer?

    public init() {
        setupRecognizer()
        detectSupportedLocales()
    }

    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: selectedLocaleOption.locale)
    }

    private func detectSupportedLocales() {
        let supported = SFSpeechRecognizer.supportedLocales()
        var list: [TranscriptionLocaleOption] = []

        for item in TranscriptionLocaleOption.recommendedLocales {
            if supported.contains(item.locale) {
                list.append(item)
            }
        }

        if !list.isEmpty {
            self.availableLocales = list
            if !list.contains(where: { $0.id == selectedLocaleOption.id }) {
                self.selectedLocaleOption = list[0]
            }
        }
    }

    /// Solicita permisos de Micrófono y Reconocimiento de Voz a macOS.
    public func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micAuthorized: Bool
        if #available(macOS 14.0, *) {
            micAuthorized = await AVAudioApplication.requestRecordPermission()
        } else {
            micAuthorized = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        self.isAuthorized = speechAuthorized && micAuthorized
        if !speechAuthorized || !micAuthorized {
            self.errorMessage = String(localized: "Se requieren permisos de Micrófono y Reconocimiento de Voz para dictar.")
        }
        return self.isAuthorized
    }

    /// Inicia la grabación del micrófono y la transcripción incremental en vivo.
    public func startRecording(onAppendText: @escaping (String) -> Void) async {
        guard !isRecording else { return }

        let permissionsOk = await requestPermissions()
        guard permissionsOk else { return }

        // Limpiar estado previo
        errorMessage = nil
        liveTranscript = ""
        recordingDuration = 0
        stopRecordingInternal()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            self.errorMessage = String(localized: "El reconocedor de voz no está disponible para este idioma.")
            return
        }

        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true

            // Preferir reconocimiento on-device si el hardware y la locale lo soportan
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            self.isRecording = true
            startTimer()

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let formatted = result.bestTranscription.formattedString
                    self.liveTranscript = formatted
                    onAppendText(formatted)
                }

                if let error = error {
                    // Si no es una cancelación intencionada, reportar el error
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 203 { // 203 = cancel
                        self.errorMessage = error.localizedDescription
                    }
                    self.stopRecording()
                }

                if result?.isFinal == true {
                    self.stopRecording()
                }
            }
        } catch {
            self.errorMessage = String(localized: "No se pudo inicializar la captura de audio: \(error.localizedDescription)")
            stopRecordingInternal()
        }
    }

    /// Detiene la grabación y finaliza la sesión de transcripción.
    public func stopRecording() {
        guard isRecording else { return }
        stopRecordingInternal()
    }

    private func stopRecordingInternal() {
        stopTimer()
        isRecording = false

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func startTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordingDuration += 1
            }
        }
    }

    private func stopTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    /// Formatea la duración transcurrida en mm:ss
    public var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
