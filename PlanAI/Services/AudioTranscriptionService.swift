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

/// Contenedor thread-safe para que el tap de Core Audio apunte siempre a la petición activa.
private final class RecognitionRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func update(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
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
    private let requestBox = RecognitionRequestBox()
    private var durationTimer: Timer?
    private var textAppendHandler: (@MainActor (String) -> Void)?

    /// Texto ya confirmado de segmentos anteriores (pausas / isFinal).
    private var committedTranscript: String = ""
    /// Hipótesis actual del segmento en curso.
    private var currentPartial: String = ""
    /// Invalida callbacks de tareas canceladas al reiniciar el reconocimiento.
    private var recognitionGeneration: UInt64 = 0
    private var isStopping: Bool = false
    private var lastRestartAt: Date?

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

    /// Solicita permisos de Micrófono y Reconocimiento de Voz a macOS garantizando ejecución en la cola principal.
    public func requestPermissions() async -> Bool {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechGranted: Bool

        if speechStatus == .notDetermined {
            speechGranted = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    SFSpeechRecognizer.requestAuthorization { status in
                        DispatchQueue.main.async {
                            continuation.resume(returning: status == .authorized)
                        }
                    }
                }
            }
        } else {
            speechGranted = (speechStatus == .authorized)
        }

        let micGranted: Bool
        if #available(macOS 14.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        }

        self.isAuthorized = speechGranted && micGranted
        if !self.isAuthorized {
            self.errorMessage = String(localized: "Se requieren permisos de Micrófono y Reconocimiento de Voz para dictar.")
        }
        return self.isAuthorized
    }

    /// Inicia la grabación del micrófono y la transcripción incremental en vivo.
    public func startRecording(onAppendText: @escaping @MainActor (String) -> Void) async {
        guard !isRecording else { return }

        let permissionsOk = await requestPermissions()
        guard permissionsOk else { return }

        errorMessage = nil
        stopRecordingInternal()
        liveTranscript = ""
        recordingDuration = 0
        committedTranscript = ""
        currentPartial = ""
        isStopping = false
        lastRestartAt = nil
        textAppendHandler = onAppendText

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            self.errorMessage = String(localized: "El reconocedor de voz no está disponible para este idioma.")
            return
        }

        do {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                self.errorMessage = String(localized: "No se detectó un dispositivo de entrada de audio válido.")
                return
            }

            inputNode.removeTap(onBus: 0)

            // El tap se instala una vez y sigue a la petición vigente vía requestBox.
            let tapBlock = Self.makeAudioTapBlock(requestBox: requestBox)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat, block: tapBlock)

            audioEngine.prepare()
            try audioEngine.start()

            self.isRecording = true
            startTimer()
            beginRecognitionTask(recognizer: recognizer)
        } catch {
            self.errorMessage = String(localized: "No se pudo inicializar la captura de audio: \(error.localizedDescription)")
            stopRecordingInternal()
        }
    }

    /// Detiene la grabación y finaliza la sesión de transcripción.
    public func stopRecording() {
        guard isRecording else { return }
        isStopping = true
        commitPartialIfNeeded()
        publishTranscript()
        stopRecordingInternal()
    }

    private func handleRecognitionUpdate(text: String?, isFinal: Bool, error: Error?, generation: UInt64) {
        guard generation == recognitionGeneration, isRecording, !isStopping else { return }

        if let text {
            currentPartial = text
            publishTranscript()
        }

        if let error {
            let nsError = error as NSError
            if Self.isRecoverableSpeechInterruption(nsError) {
                commitPartialIfNeeded()
                publishTranscript()
                restartRecognition()
                return
            }
            errorMessage = error.localizedDescription
            commitPartialIfNeeded()
            publishTranscript()
            stopRecording()
            return
        }

        if isFinal {
            commitPartialIfNeeded()
            publishTranscript()
            restartRecognition()
        }
    }

    private func beginRecognitionTask(recognizer: SFSpeechRecognizer) {
        recognitionGeneration += 1
        let generation = recognitionGeneration

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        let request = Self.makeRecognitionRequest(supportsOnDevice: recognizer.supportsOnDeviceRecognition)
        recognitionRequest = request
        requestBox.update(request)

        recognitionTask = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeRecognitionHandler { [weak self] text, isFinal, error in
                Task { @MainActor in
                    self?.handleRecognitionUpdate(
                        text: text,
                        isFinal: isFinal,
                        error: error,
                        generation: generation
                    )
                }
            }
        )
    }

    private func restartRecognition() {
        guard isRecording, !isStopping else { return }
        if let lastRestartAt, Date().timeIntervalSince(lastRestartAt) < 0.2, recognitionTask != nil {
            return
        }
        lastRestartAt = Date()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = String(localized: "El reconocedor de voz no está disponible para este idioma.")
            stopRecording()
            return
        }

        beginRecognitionTask(recognizer: recognizer)
    }

    private func commitPartialIfNeeded() {
        let piece = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        currentPartial = ""
        guard !piece.isEmpty else { return }

        if committedTranscript.isEmpty {
            committedTranscript = piece
            return
        }

        if committedTranscript.hasSuffix(piece) {
            return
        }

        committedTranscript += " " + piece
    }

    private func combinedTranscript() -> String {
        let committed = committedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if committed.isEmpty { return partial }
        if partial.isEmpty { return committed }
        if committed.hasSuffix(partial) { return committed }
        return committed + " " + partial
    }

    private func publishTranscript() {
        let combined = combinedTranscript()
        liveTranscript = combined
        textAppendHandler?(combined)
    }

    private func stopRecordingInternal() {
        recognitionGeneration += 1
        isStopping = true
        stopTimer()
        isRecording = false
        textAppendHandler = nil
        requestBox.update(nil)

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
            Task { @MainActor in
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

    private static func makeRecognitionRequest(supportsOnDevice: Bool) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if supportsOnDevice {
            request.requiresOnDeviceRecognition = true
        }
        return request
    }

    /// Timeouts de silencio, fin de segmento y límite ~1 min: se reinicia la tarea, no la grabación.
    private static func isRecoverableSpeechInterruption(_ error: NSError) -> Bool {
        if error.domain == "kAFAssistantErrorDomain" {
            switch error.code {
            case 203, 209, 216, 1101, 1110:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Cierre de tap sin aislamiento MainActor: Core Audio lo llama en un hilo de tiempo real.
    nonisolated private static func makeAudioTapBlock(
        requestBox: RecognitionRequestBox
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            requestBox.append(buffer)
        }
    }

    /// Cierre de Speech sin aislamiento MainActor: el framework lo llama en una cola de fondo.
    nonisolated private static func makeRecognitionHandler(
        onUpdate: @escaping @Sendable (String?, Bool, Error?) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            onUpdate(
                result?.bestTranscription.formattedString,
                result?.isFinal == true,
                error
            )
        }
    }
}
