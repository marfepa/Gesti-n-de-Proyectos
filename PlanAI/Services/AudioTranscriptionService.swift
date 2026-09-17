import Foundation
import SwiftUI
import Speech
import AVFoundation

/// Estados del ciclo de vida de captura y transcripción offline.
public enum TranscriptionPhase: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case completed
    case error(String)

    public var isRecording: Bool {
        self == .recording
    }

    public var isTranscribing: Bool {
        self == .transcribing
    }
}

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

/// Grabador thread-safe para volcar buffers de audio de Core Audio directamente a un archivo de disco.
private final class AudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private(set) var fileURL: URL?

    func startWriting(to url: URL, format: AVAudioFormat) throws {
        lock.lock()
        defer { lock.unlock() }
        self.fileURL = url
        self.audioFile = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func write(buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        try? audioFile?.write(from: buffer)
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        audioFile = nil
    }
}

/// Servicio observable que orquesta la captura de audio a archivo temporal y su posterior transcripción offline.
@Observable
@MainActor
public final class AudioTranscriptionService {
    public var phase: TranscriptionPhase = .idle
    public var recordingDuration: TimeInterval = 0
    public var transcriptionProgress: Double = 0.0
    public var transcribedText: String = ""
    public var errorMessage: String?
    public var isAuthorized: Bool = false
    public var recordedFileURL: URL?

    public var isRecording: Bool {
        phase == .recording
    }

    public var isTranscribing: Bool {
        phase == .transcribing
    }

    public var selectedLocaleOption: TranscriptionLocaleOption = TranscriptionLocaleOption.recommendedLocales[0]
    public var availableLocales: [TranscriptionLocaleOption] = TranscriptionLocaleOption.recommendedLocales

    private let audioEngine = AVAudioEngine()
    private let fileWriter = AudioFileWriter()
    private var durationTimer: Timer?
    private var activeTranscriptionTask: Task<String, Error>?

    public init() {
        detectSupportedLocales()
    }

    deinit {
        // En Swift 6, MainActor class deinit corre nonisolated
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
            self.errorMessage = String(localized: "Se requieren permisos de Micrófono y Reconocimiento de Voz para transcribir.")
        }
        return self.isAuthorized
    }

    /// Comienza la grabación de audio del micrófono y escribe los buffers a un archivo temporal .caf en disco.
    public func startRecording() async {
        guard !isRecording && !isTranscribing else { return }

        let hasPermissions = await requestPermissions()
        guard hasPermissions else { return }

        // Limpiar estado y grabación previa completamente
        stopEngineIfRunning()
        cleanupTempFile()
        self.errorMessage = nil
        self.transcribedText = ""
        self.transcriptionProgress = 0.0

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("planai_rec_\(UUID().uuidString).caf")
        self.recordedFileURL = fileURL

        do {
            // Resetear el graph de audio para evitar kAudioUnitErr_Uninitialized (-10877)
            audioEngine.reset()

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                throw NSError(domain: "PlanAI.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Formato de micrófono no válido."])
            }

            try fileWriter.startWriting(to: fileURL, format: recordingFormat)

            inputNode.removeTap(onBus: 0)
            let writer = self.fileWriter
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: recordingFormat) { buffer, _ in
                writer.write(buffer: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            self.phase = .recording
            self.recordingDuration = 0
            startDurationTimer()
        } catch {
            stopEngineIfRunning()
            self.errorMessage = error.localizedDescription
            self.phase = .error(error.localizedDescription)
            cleanupTempFile()
        }
    }

    /// Detiene la grabación del micrófono y cierra el archivo temporal.
    public func stopRecording() {
        guard isRecording else { return }

        stopDurationTimer()
        stopEngineIfRunning()
        fileWriter.finish()

        self.phase = .idle
    }

    /// Detiene el motor de audio de forma segura si está corriendo.
    private func stopEngineIfRunning() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    /// Transcribe el archivo previamente grabado utilizando transcripción offline on-device.
    public func transcribeRecordedAudio() async throws -> String {
        guard let fileURL = recordedFileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "PlanAI.Audio", code: 2, userInfo: [NSLocalizedDescriptionKey: "No hay ningún archivo de audio grabado para transcribir."])
        }

        self.phase = .transcribing
        self.transcriptionProgress = 0.0
        self.errorMessage = nil

        let locale = selectedLocaleOption.locale

        let task = Task<String, Error> {
            #if canImport(Speech)
            if #available(macOS 26.0, *) {
                if SpeechTranscriber.isAvailable,
                   let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                    return try await self.transcribeWithSpeechTranscriber(fileURL: fileURL, locale: resolvedLocale)
                }
            }
            #endif

            // Fallback robusto offline mediante SFSpeechURLRecognitionRequest
            return try await self.transcribeWithSpeechURLRequest(fileURL: fileURL, locale: locale)
        }

        self.activeTranscriptionTask = task

        do {
            let resultText = try await task.value
            self.transcribedText = resultText
            self.phase = .completed
            self.transcriptionProgress = 1.0
            cleanupTempFile()
            return resultText
        } catch is CancellationError {
            self.phase = .idle
            self.errorMessage = String(localized: "Transcripción cancelada.")
            throw CancellationError()
        } catch {
            self.phase = .error(error.localizedDescription)
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Cancela cualquier transcripción en curso o grabación activa y restablece el estado.
    public func cancel() {
        if isRecording {
            stopDurationTimer()
        }
        stopEngineIfRunning()
        fileWriter.finish()
        activeTranscriptionTask?.cancel()
        activeTranscriptionTask = nil
        cleanupTempFile()
        self.phase = .idle
        self.transcriptionProgress = 0.0
    }

    /// Limpia el archivo temporal de grabación en disco.
    public func cleanupTempFile() {
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
            self.recordedFileURL = nil
        }
    }

    // MARK: - Motores de Transcripción

    #if canImport(Speech)
    @available(macOS 26.0, *)
    private func transcribeWithSpeechTranscriber(fileURL: URL, locale: Locale) async throws -> String {
        var didReserve = false
        do {
            try await AssetInventory.reserve(locale: locale)
            didReserve = true
        } catch {
            // Ya reservado o no requerido
        }

        defer {
            if didReserve {
                Task {
                    await AssetInventory.release(reservedLocale: locale)
                }
            }
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        try Task.checkCancellation()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: fileURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 1.0

        let resultsTask = Task<String, Error> {
            var finalizedSegments: [String] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isFinal && !text.isEmpty {
                    finalizedSegments.append(text)
                }
                let elapsed = result.range.end.seconds
                if duration > 0 && elapsed.isFinite {
                    let progress = min(0.95, max(0.05, elapsed / duration))
                    await MainActor.run {
                        self.transcriptionProgress = progress
                    }
                }
            }
            return finalizedSegments.joined(separator: " ")
        }

        let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile)
        if let lastSampleTime {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let result = try await resultsTask.value
        return result
    }
    #endif

    private func transcribeWithSpeechURLRequest(fileURL: URL, locale: Locale) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES")),
              recognizer.isAvailable else {
            throw NSError(domain: "PlanAI.Audio", code: 3, userInfo: [NSLocalizedDescriptionKey: "Reconocedor de voz no disponible para este idioma."])
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var finalTranscript = ""

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let result = result else { return }
                let current = result.bestTranscription.formattedString

                Task { @MainActor in
                    self?.transcriptionProgress = min(0.9, (self?.transcriptionProgress ?? 0.0) + 0.1)
                }

                if result.isFinal {
                    finalTranscript = current
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: finalTranscript)
                    }
                }
            }

            // Timeout de seguridad de 60 segundos
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if !hasResumed {
                    hasResumed = true
                    task.cancel()
                    continuation.resume(returning: finalTranscript)
                }
            }
        }
    }

    // MARK: - Timers y Helpers

    private func startDurationTimer() {
        durationTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordingDuration += 0.1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    public var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
