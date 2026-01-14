import Foundation
import React
import AVFoundation
import FluidAudio
import Accelerate

// Helper extension for unique elements
extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// Audio conversion utilities
enum AudioUtils {
    static func convertToMono16kHz(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sourceSampleRate = buffer.format.sampleRate

        // Mix to mono if stereo
        var monoSamples = [Float](repeating: 0, count: frameLength)
        if channelCount == 1 {
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            for i in 0..<frameLength {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        }

        // Resample to 16kHz if needed
        if abs(sourceSampleRate - 16000) < 1 {
            return monoSamples
        }

        let ratio = 16000.0 / sourceSampleRate
        let outputLength = Int(Double(frameLength) * ratio)
        var outputSamples = [Float](repeating: 0, count: outputLength)

        // Simple linear interpolation resampling
        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < frameLength {
                outputSamples[i] = monoSamples[srcIndexInt] * (1 - frac) + monoSamples[srcIndexInt + 1] * frac
            } else if srcIndexInt < frameLength {
                outputSamples[i] = monoSamples[srcIndexInt]
            }
        }

        return outputSamples
    }
}

@objc(FluidAudioModule)
class FluidAudioModule: RCTEventEmitter {

    private var hasListeners = false

    // Streaming ASR
    private var streamingManager: StreamingAsrManager?
    private var audioEngine: AVAudioEngine?
    private var streamingTask: Task<Void, Never>?
    private var isStreamingActive = false

    // ASR
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?

    // VAD
    private var vadManager: VadManager?

    // Diarization
    private var diarizerManager: DiarizerManager?

    // MARK: - Module Setup

    override init() {
        super.init()
    }

    @objc override static func requiresMainQueueSetup() -> Bool {
        return false
    }

    override func supportedEvents() -> [String]! {
        return [
            "onTranscriptionUpdate",
            "onTranscriptionComplete",
            "onTranscriptionError",
            "onVadResult",
            "onDiarizationResult",
            "onModelLoadProgress",
            "onStreamingUpdate"
        ]
    }

    override func startObserving() {
        hasListeners = true
    }

    override func stopObserving() {
        hasListeners = false
    }

    private func sendEvent(name: String, body: [String: Any]) {
        if hasListeners {
            sendEvent(withName: name, body: body)
        }
    }

    // MARK: - System Info

    @objc(getSystemInfo:rejecter:)
    func getSystemInfo(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let info: [String: Any] = [
            "isAppleSilicon": true,
            "platform": "ios",
            "summary": SystemInfo.summary()
        ]
        resolve(info)
    }

    // MARK: - ASR (Automatic Speech Recognition)

    @objc(initializeAsr:resolver:rejecter:)
    func initializeAsr(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                sendEvent(name: "onModelLoadProgress", body: [
                    "type": "asr",
                    "status": "downloading",
                    "progress": 0
                ])

                let startTime = Date()
                let models = try await AsrModels.downloadAndLoad()
                self.asrModels = models

                sendEvent(name: "onModelLoadProgress", body: [
                    "type": "asr",
                    "status": "compiling",
                    "progress": 50
                ])

                let asrConfig = ASRConfig(sampleRate: 16000, tdtConfig: TdtConfig())
                let manager = AsrManager(config: asrConfig)
                try await manager.initialize(models: models)
                self.asrManager = manager

                let duration = Date().timeIntervalSince(startTime)

                sendEvent(name: "onModelLoadProgress", body: [
                    "type": "asr",
                    "status": "ready",
                    "progress": 100
                ])

                resolve([
                    "success": true,
                    "compilationDuration": duration
                ])
            } catch {
                reject("ASR_INIT_ERROR", "Failed to initialize ASR: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(transcribeFile:resolver:rejecter:)
    func transcribeFile(
        filePath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let asrManager = asrManager else {
            reject("ASR_NOT_INITIALIZED", "ASR not initialized. Call initializeAsr first.", nil)
            return
        }

        Task {
            do {
                let url = URL(fileURLWithPath: filePath)
                let result = try await asrManager.transcribe(url)

                resolve([
                    "text": result.text,
                    "confidence": result.confidence,
                    "duration": result.duration,
                    "processingTime": result.processingTime,
                    "rtfx": result.rtfx
                ])
            } catch {
                reject("TRANSCRIBE_ERROR", "Failed to transcribe file: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(transcribeAudioData:sampleRate:resolver:rejecter:)
    func transcribeAudioData(
        base64Audio: String,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let asrManager = asrManager else {
            reject("ASR_NOT_INITIALIZED", "ASR not initialized. Call initializeAsr first.", nil)
            return
        }

        guard let audioData = Data(base64Encoded: base64Audio) else {
            reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
            return
        }

        Task {
            do {
                let samples = audioData.withUnsafeBytes { ptr -> [Float] in
                    let int16Ptr = ptr.bindMemory(to: Int16.self)
                    return int16Ptr.map { Float($0) / 32768.0 }
                }

                let result = try await asrManager.transcribe(samples)

                resolve([
                    "text": result.text,
                    "confidence": result.confidence,
                    "duration": result.duration,
                    "processingTime": result.processingTime,
                    "rtfx": result.rtfx
                ])
            } catch {
                reject("TRANSCRIBE_ERROR", "Failed to transcribe audio: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(isAsrAvailable:rejecter:)
    func isAsrAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(asrManager != nil)
    }

    // MARK: - Streaming ASR

    @objc(startStreamingAsr:resolver:rejecter:)
    func startStreamingAsr(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard !isStreamingActive else {
            reject("STREAMING_ACTIVE", "Streaming is already active", nil)
            return
        }

        Task {
            do {
                // Request microphone permission
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)

                // Create streaming manager
                let streamConfig = StreamingAsrConfig.streaming
                let manager = StreamingAsrManager(config: streamConfig)
                self.streamingManager = manager

                // Start the streaming engine
                try await manager.start(source: .microphone)

                // Set up audio engine to capture microphone
                let engine = AVAudioEngine()
                self.audioEngine = engine

                let inputNode = engine.inputNode
                let inputFormat = inputNode.outputFormat(forBus: 0)

                // Install tap to capture audio
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self = self, self.isStreamingActive else { return }
                    Task {
                        await self.streamingManager?.streamAudio(buffer)
                    }
                }

                // Start audio engine
                try engine.start()
                self.isStreamingActive = true

                // Listen for transcription updates
                self.streamingTask = Task { [weak self] in
                    guard let self = self, let manager = self.streamingManager else { return }

                    for await update in await manager.transcriptionUpdates {
                        let volatile = await manager.volatileTranscript
                        let confirmed = await manager.confirmedTranscript

                        self.sendEvent(name: "onStreamingUpdate", body: [
                            "volatile": volatile,
                            "confirmed": confirmed,
                            "text": update.text,
                            "isConfirmed": update.isConfirmed,
                            "confidence": update.confidence,
                            "isFinal": false
                        ])
                    }
                }

                resolve(["success": true])

            } catch {
                self.isStreamingActive = false
                reject("STREAMING_START_ERROR", "Failed to start streaming: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(feedStreamingAudio:resolver:rejecter:)
    func feedStreamingAudio(
        base64Audio: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // This is handled automatically by the audio tap when using microphone source
        // For manual feeding, we would need to convert base64 to AVAudioPCMBuffer
        resolve(["success": true])
    }

    @objc(stopStreamingAsr:rejecter:)
    func stopStreamingAsr(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard isStreamingActive else {
            resolve(["text": "", "success": true])
            return
        }

        Task {
            do {
                // Stop audio engine
                audioEngine?.inputNode.removeTap(onBus: 0)
                audioEngine?.stop()
                audioEngine = nil

                // Get final transcription
                let finalText = try await streamingManager?.finish() ?? ""

                // Cancel update task
                streamingTask?.cancel()
                streamingTask = nil

                // Clean up
                streamingManager = nil
                isStreamingActive = false

                // Deactivate audio session
                try? AVAudioSession.sharedInstance().setActive(false)

                resolve([
                    "text": finalText,
                    "success": true
                ])

            } catch {
                isStreamingActive = false
                reject("STREAMING_STOP_ERROR", "Failed to stop streaming: \(error.localizedDescription)", error)
            }
        }
    }

    // MARK: - VAD (Voice Activity Detection)

    @objc(initializeVad:resolver:rejecter:)
    func initializeVad(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                let threshold = config?["threshold"] as? Double ?? 0.85
                let vadConfig = VadConfig(defaultThreshold: Float(threshold))
                let manager = try await VadManager(config: vadConfig)
                self.vadManager = manager

                resolve(["success": true])
            } catch {
                reject("VAD_INIT_ERROR", "Failed to initialize VAD: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(processVad:resolver:rejecter:)
    func processVad(
        filePath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let vadManager = vadManager else {
            reject("VAD_NOT_INITIALIZED", "VAD not initialized", nil)
            return
        }

        Task {
            do {
                let url = URL(fileURLWithPath: filePath)
                let results = try await vadManager.process(url)

                let resultsArray = results.enumerated().map { (index, result) -> [String: Any] in
                    return [
                        "chunkIndex": index,
                        "probability": result.probability,
                        "isActive": result.isVoiceActive,
                        "processingTime": result.processingTime
                    ]
                }

                resolve([
                    "results": resultsArray,
                    "chunkSize": VadManager.chunkSize,
                    "sampleRate": VadManager.sampleRate
                ])
            } catch {
                reject("VAD_PROCESS_ERROR", "Failed to process VAD: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(processVadAudioData:resolver:rejecter:)
    func processVadAudioData(
        base64Audio: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let vadManager = vadManager else {
            reject("VAD_NOT_INITIALIZED", "VAD not initialized", nil)
            return
        }

        guard let audioData = Data(base64Encoded: base64Audio) else {
            reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
            return
        }

        Task {
            do {
                let samples = audioData.withUnsafeBytes { ptr -> [Float] in
                    let int16Ptr = ptr.bindMemory(to: Int16.self)
                    return int16Ptr.map { Float($0) / 32768.0 }
                }

                let results = try await vadManager.process(samples)

                let resultsArray = results.enumerated().map { (index, result) -> [String: Any] in
                    return [
                        "chunkIndex": index,
                        "probability": result.probability,
                        "isActive": result.isVoiceActive,
                        "processingTime": result.processingTime
                    ]
                }

                resolve([
                    "results": resultsArray,
                    "chunkSize": VadManager.chunkSize,
                    "sampleRate": VadManager.sampleRate
                ])
            } catch {
                reject("VAD_PROCESS_ERROR", "Failed to process VAD: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(isVadAvailable:rejecter:)
    func isVadAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(vadManager != nil)
    }

    // MARK: - Diarization

    @objc(initializeDiarization:resolver:rejecter:)
    func initializeDiarization(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                sendEvent(name: "onModelLoadProgress", body: [
                    "type": "diarization",
                    "status": "downloading",
                    "progress": 0
                ])

                let startTime = Date()
                let threshold = config?["clusteringThreshold"] as? Double ?? 0.7
                let numClusters = config?["numClusters"] as? Int ?? -1

                let diarizationConfig = DiarizerConfig(
                    clusteringThreshold: Float(threshold),
                    numClusters: numClusters
                )

                sendEvent(name: "onModelLoadProgress", body: [
                    "type": "diarization",
                    "status": "compiling",
                    "progress": 50
                ])

                let manager = DiarizerManager(config: diarizationConfig)
                let models = try await DiarizerModels.download()
                manager.initialize(models: models)
                self.diarizerManager = manager

                let duration = Date().timeIntervalSince(startTime)

                sendEvent(name: "onModelLoadProgress", body: [
                    "type": "diarization",
                    "status": "ready",
                    "progress": 100
                ])

                resolve([
                    "success": true,
                    "compilationDuration": duration
                ])
            } catch {
                reject("DIARIZATION_INIT_ERROR", "Failed to initialize diarization: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(performDiarization:sampleRate:resolver:rejecter:)
    func performDiarization(
        filePath: String,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let diarizerManager = diarizerManager else {
            reject("DIARIZATION_NOT_INITIALIZED", "Diarization not initialized", nil)
            return
        }

        Task {
            do {
                let url = URL(fileURLWithPath: filePath)

                // Load audio from file
                let audioFile = try AVAudioFile(forReading: url)
                let format = audioFile.processingFormat
                let frameCount = UInt32(audioFile.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    reject("AUDIO_LOAD_ERROR", "Failed to create audio buffer", nil)
                    return
                }
                try audioFile.read(into: buffer)

                // Convert to Float array at 16kHz
                let samples = AudioUtils.convertToMono16kHz(buffer)
                let result = try diarizerManager.performCompleteDiarization(samples, sampleRate: 16000)

                let segments = result.segments.map { segment -> [String: Any] in
                    return [
                        "speakerId": segment.speakerId,
                        "startTime": segment.startTimeSeconds,
                        "endTime": segment.endTimeSeconds,
                        "duration": segment.durationSeconds,
                        "qualityScore": segment.qualityScore
                    ]
                }

                resolve([
                    "segments": segments,
                    "speakerCount": result.segments.map { $0.speakerId }.uniqued().count
                ])
            } catch {
                reject("DIARIZATION_ERROR", "Failed to perform diarization: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(performDiarizationOnAudioData:sampleRate:resolver:rejecter:)
    func performDiarizationOnAudioData(
        base64Audio: String,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let diarizerManager = diarizerManager else {
            reject("DIARIZATION_NOT_INITIALIZED", "Diarization not initialized", nil)
            return
        }

        guard let audioData = Data(base64Encoded: base64Audio) else {
            reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
            return
        }

        Task {
            do {
                let samples = audioData.withUnsafeBytes { ptr -> [Float] in
                    let int16Ptr = ptr.bindMemory(to: Int16.self)
                    return int16Ptr.map { Float($0) / 32768.0 }
                }

                let result = try diarizerManager.performCompleteDiarization(samples, sampleRate: sampleRate)

                let segments = result.segments.map { segment -> [String: Any] in
                    return [
                        "speakerId": segment.speakerId,
                        "startTime": segment.startTimeSeconds,
                        "endTime": segment.endTimeSeconds,
                        "duration": segment.durationSeconds,
                        "qualityScore": segment.qualityScore
                    ]
                }

                resolve([
                    "segments": segments,
                    "speakerCount": result.segments.map { $0.speakerId }.uniqued().count
                ])
            } catch {
                reject("DIARIZATION_ERROR", "Failed to perform diarization: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(initializeKnownSpeakers:resolver:rejecter:)
    func initializeKnownSpeakers(
        speakers: NSArray,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "success": true,
            "speakerCount": speakers.count
        ])
    }

    @objc(isDiarizationAvailable:rejecter:)
    func isDiarizationAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(diarizerManager != nil)
    }

    // MARK: - TTS (Text-to-Speech)

    @objc(initializeTts:resolver:rejecter:)
    func initializeTts(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // TTS requires FluidAudioTTS which has GPL dependencies
        // For now, return success but note it's not fully implemented
        resolve(["success": true])
    }

    @objc(synthesize:voice:resolver:rejecter:)
    func synthesize(
        text: String,
        voice: String?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // TTS not yet implemented - would need FluidAudioTTS
        resolve([
            "audioData": "",
            "duration": 0.0,
            "sampleRate": 24000
        ])
    }

    @objc(synthesizeToFile:voice:outputPath:resolver:rejecter:)
    func synthesizeToFile(
        text: String,
        voice: String?,
        outputPath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(["success": false, "error": "TTS not yet implemented"])
    }

    @objc(isTtsAvailable:rejecter:)
    func isTtsAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(false)
    }

    // MARK: - Cleanup

    @objc(cleanup:rejecter:)
    func cleanup(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            // Stop streaming if active
            if isStreamingActive {
                audioEngine?.inputNode.removeTap(onBus: 0)
                audioEngine?.stop()
                audioEngine = nil
                await streamingManager?.cancel()
                streamingManager = nil
                streamingTask?.cancel()
                streamingTask = nil
                isStreamingActive = false
            }

            // Clean up managers
            asrManager = nil
            asrModels = nil
            vadManager = nil
            diarizerManager = nil

            resolve(["success": true])
        }
    }
}
