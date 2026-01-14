import Foundation
import React
import AVFoundation
import FluidAudio

#if canImport(FluidAudioTTS)
import FluidAudioTTS
private let ttsAvailable = true
#else
private let ttsAvailable = false
#endif

@objc(FluidAudioModule)
class FluidAudioModule: RCTEventEmitter {

    // MARK: - Properties

    private var asrManager: AsrManager?
    private var streamingAsrManager: StreamingAsrManager?
    private var vadManager: VadManager?
    private var diarizerManager: DiarizerManager?
    #if canImport(FluidAudioTTS)
    private var ttsManager: TtsManager?
    #endif
    private var audioConverter: AudioConverter?

    private var hasListeners = false
    private var streamingTask: Task<Void, Never>?

    // MARK: - Module Setup

    override init() {
        super.init()
        audioConverter = AudioConverter()
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

    // MARK: - System Info

    @objc(getSystemInfo:rejecter:)
    func getSystemInfo(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let info: [String: Any] = [
            "isAppleSilicon": SystemInfo.isAppleSilicon,
            "isIntelMac": SystemInfo.isIntelMac,
            "platform": {
                #if os(iOS)
                return "ios"
                #elseif os(macOS)
                return "macos"
                #else
                return "unknown"
                #endif
            }(),
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
                var asrConfig = ASRConfig.default

                if let configDict = config {
                    if let sampleRate = configDict["sampleRate"] as? Int {
                        asrConfig.sampleRate = sampleRate
                    }
                    if let streamingEnabled = configDict["streamingEnabled"] as? Bool {
                        asrConfig.streamingEnabled = streamingEnabled
                    }
                }

                asrManager = AsrManager(config: asrConfig)

                if hasListeners {
                    sendEvent(withName: "onModelLoadProgress", body: ["status": "downloading", "progress": 0])
                }

                let models = try await AsrModels.downloadAndLoad()
                try await asrManager?.initialize(models: models)

                if hasListeners {
                    sendEvent(withName: "onModelLoadProgress", body: ["status": "ready", "progress": 100])
                }

                resolve([
                    "success": true,
                    "compilationDuration": models.compilationDuration
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
        Task {
            do {
                guard let asr = asrManager else {
                    reject("ASR_NOT_INITIALIZED", "ASR manager not initialized. Call initializeAsr first.", nil)
                    return
                }

                let url = URL(fileURLWithPath: filePath)
                let result = try await asr.transcribe(file: url)

                resolve(asrResultToDict(result))
            } catch {
                reject("TRANSCRIBE_ERROR", "Transcription failed: \(error.localizedDescription)", error)
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
        Task {
            do {
                guard let asr = asrManager else {
                    reject("ASR_NOT_INITIALIZED", "ASR manager not initialized. Call initializeAsr first.", nil)
                    return
                }

                guard let audioData = Data(base64Encoded: base64Audio) else {
                    reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
                    return
                }

                // Convert Data to Float samples
                let samples = audioDataToFloatSamples(audioData)

                // Resample if necessary
                var processedSamples = samples
                if sampleRate != 16000, let converter = audioConverter {
                    processedSamples = try converter.resample(samples, from: Double(sampleRate))
                }

                let result = try await asr.transcribe(samples: processedSamples)
                resolve(asrResultToDict(result))
            } catch {
                reject("TRANSCRIBE_ERROR", "Transcription failed: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(isAsrAvailable:rejecter:)
    func isAsrAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(asrManager?.isAvailable ?? false)
    }

    // MARK: - Streaming ASR

    @objc(startStreamingAsr:resolver:rejecter:)
    func startStreamingAsr(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                var streamingConfig = StreamingAsrConfig.default

                if let configDict = config {
                    if let chunkDuration = configDict["chunkDuration"] as? Double {
                        streamingConfig.chunkDuration = chunkDuration
                    }
                }

                let sourceString = config?["source"] as? String ?? "microphone"
                let source: AudioSource = sourceString == "system" ? .system : .microphone

                streamingAsrManager = StreamingAsrManager(config: streamingConfig)
                try await streamingAsrManager?.start(source: source)

                // Start listening for updates
                streamingTask = Task {
                    guard let manager = streamingAsrManager else { return }

                    for await update in await manager.transcriptionUpdates {
                        if hasListeners {
                            sendEvent(withName: "onStreamingUpdate", body: [
                                "volatile": await manager.volatileTranscript,
                                "confirmed": await manager.confirmedTranscript,
                                "isFinal": false
                            ])
                        }
                    }
                }

                resolve(["success": true])
            } catch {
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
        Task {
            guard let manager = streamingAsrManager else {
                reject("STREAMING_NOT_STARTED", "Streaming ASR not started. Call startStreamingAsr first.", nil)
                return
            }

            guard let audioData = Data(base64Encoded: base64Audio) else {
                reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
                return
            }

            // Convert to AVAudioPCMBuffer
            guard let buffer = dataToAudioBuffer(audioData) else {
                reject("BUFFER_ERROR", "Failed to create audio buffer", nil)
                return
            }

            await manager.streamAudio(buffer)
            resolve(["success": true])
        }
    }

    @objc(stopStreamingAsr:rejecter:)
    func stopStreamingAsr(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                streamingTask?.cancel()
                streamingTask = nil

                guard let manager = streamingAsrManager else {
                    resolve(["text": "", "success": true])
                    return
                }

                let finalText = try await manager.finish()
                streamingAsrManager = nil

                if hasListeners {
                    sendEvent(withName: "onStreamingUpdate", body: [
                        "volatile": "",
                        "confirmed": finalText,
                        "isFinal": true
                    ])
                }

                resolve([
                    "text": finalText,
                    "success": true
                ])
            } catch {
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
                var vadConfig = VadConfig.default

                if let configDict = config {
                    if let threshold = configDict["threshold"] as? Float {
                        vadConfig.defaultThreshold = threshold
                    }
                    if let debugMode = configDict["debugMode"] as? Bool {
                        vadConfig.debugMode = debugMode
                    }
                }

                vadManager = try await VadManager(config: vadConfig)
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
        Task {
            do {
                guard let vad = vadManager else {
                    reject("VAD_NOT_INITIALIZED", "VAD manager not initialized. Call initializeVad first.", nil)
                    return
                }

                let url = URL(fileURLWithPath: filePath)
                let results = try await vad.process(url)

                let resultDicts = results.map { result -> [String: Any] in
                    [
                        "chunkIndex": result.chunkIndex,
                        "probability": result.probability,
                        "isActive": result.isActive,
                        "processingTime": result.processingTime
                    ]
                }

                resolve([
                    "results": resultDicts,
                    "chunkSize": VadManager.chunkSize,
                    "sampleRate": VadManager.sampleRate
                ])
            } catch {
                reject("VAD_PROCESS_ERROR", "VAD processing failed: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(processVadAudioData:resolver:rejecter:)
    func processVadAudioData(
        base64Audio: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                guard let vad = vadManager else {
                    reject("VAD_NOT_INITIALIZED", "VAD manager not initialized. Call initializeVad first.", nil)
                    return
                }

                guard let audioData = Data(base64Encoded: base64Audio) else {
                    reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
                    return
                }

                let samples = audioDataToFloatSamples(audioData)
                let results = try await vad.process(samples)

                let resultDicts = results.map { result -> [String: Any] in
                    [
                        "chunkIndex": result.chunkIndex,
                        "probability": result.probability,
                        "isActive": result.isActive,
                        "processingTime": result.processingTime
                    ]
                }

                resolve([
                    "results": resultDicts,
                    "chunkSize": VadManager.chunkSize,
                    "sampleRate": VadManager.sampleRate
                ])
            } catch {
                reject("VAD_PROCESS_ERROR", "VAD processing failed: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(isVadAvailable:rejecter:)
    func isVadAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            let available = await vadManager?.isAvailable ?? false
            resolve(available)
        }
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
                var diarizationConfig = DiarizerConfig.default

                if let configDict = config {
                    if let clusteringThreshold = configDict["clusteringThreshold"] as? Float {
                        diarizationConfig.clusteringThreshold = clusteringThreshold
                    }
                    if let minSpeechDuration = configDict["minSpeechDuration"] as? Float {
                        diarizationConfig.minSpeechDuration = minSpeechDuration
                    }
                    if let minSilenceGap = configDict["minSilenceGap"] as? Float {
                        diarizationConfig.minSilenceGap = minSilenceGap
                    }
                    if let numClusters = configDict["numClusters"] as? Int {
                        diarizationConfig.numClusters = numClusters
                    }
                    if let debugMode = configDict["debugMode"] as? Bool {
                        diarizationConfig.debugMode = debugMode
                    }
                }

                diarizerManager = DiarizerManager(config: diarizationConfig)

                if hasListeners {
                    sendEvent(withName: "onModelLoadProgress", body: [
                        "type": "diarization",
                        "status": "downloading",
                        "progress": 0
                    ])
                }

                let models = try await DiarizerModels.downloadIfNeeded()
                diarizerManager?.initialize(models: models)

                if hasListeners {
                    sendEvent(withName: "onModelLoadProgress", body: [
                        "type": "diarization",
                        "status": "ready",
                        "progress": 100
                    ])
                }

                resolve([
                    "success": true,
                    "compilationDuration": models.compilationDuration
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
        Task {
            do {
                guard let diarizer = diarizerManager else {
                    reject("DIARIZATION_NOT_INITIALIZED", "Diarization manager not initialized. Call initializeDiarization first.", nil)
                    return
                }

                // Load audio from file
                let url = URL(fileURLWithPath: filePath)
                guard let converter = audioConverter else {
                    reject("CONVERTER_ERROR", "Audio converter not available", nil)
                    return
                }

                let samples = try converter.resampleAudioFile(url)
                let result = try diarizer.performCompleteDiarization(samples, sampleRate: 16000)

                resolve(diarizationResultToDict(result))
            } catch {
                reject("DIARIZATION_ERROR", "Diarization failed: \(error.localizedDescription)", error)
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
        Task {
            do {
                guard let diarizer = diarizerManager else {
                    reject("DIARIZATION_NOT_INITIALIZED", "Diarization manager not initialized. Call initializeDiarization first.", nil)
                    return
                }

                guard let audioData = Data(base64Encoded: base64Audio) else {
                    reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
                    return
                }

                var samples = audioDataToFloatSamples(audioData)

                // Resample if necessary
                if sampleRate != 16000, let converter = audioConverter {
                    samples = try converter.resample(samples, from: Double(sampleRate))
                }

                let result = try diarizer.performCompleteDiarization(samples, sampleRate: 16000)
                resolve(diarizationResultToDict(result))
            } catch {
                reject("DIARIZATION_ERROR", "Diarization failed: \(error.localizedDescription)", error)
            }
        }
    }

    @objc(initializeKnownSpeakers:resolver:rejecter:)
    func initializeKnownSpeakers(
        speakers: NSArray,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let diarizer = diarizerManager else {
            reject("DIARIZATION_NOT_INITIALIZED", "Diarization manager not initialized", nil)
            return
        }

        var speakerObjects: [Speaker] = []

        for speakerDict in speakers {
            guard let dict = speakerDict as? [String: Any],
                  let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let embedding = dict["embedding"] as? [Float] else {
                continue
            }

            let speaker = Speaker(
                id: id,
                name: name,
                currentEmbedding: embedding
            )
            speakerObjects.append(speaker)
        }

        diarizer.initializeKnownSpeakers(speakerObjects)
        resolve(["success": true, "speakerCount": speakerObjects.count])
    }

    @objc(isDiarizationAvailable:rejecter:)
    func isDiarizationAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(diarizerManager?.isAvailable ?? false)
    }

    // MARK: - TTS (Text-to-Speech)

    @objc(initializeTts:resolver:rejecter:)
    func initializeTts(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(FluidAudioTTS)
        Task {
            do {
                var ttsConfig = TtsConfig.default

                if let configDict = config {
                    if let debugMode = configDict["debugMode"] as? Bool {
                        ttsConfig.debugMode = debugMode
                    }
                    if let variant = configDict["variant"] as? String {
                        switch variant {
                        case "fiveSecond":
                            ttsConfig.variant = .fiveSecond
                        case "fifteenSecond":
                            ttsConfig.variant = .fifteenSecond
                        default:
                            break
                        }
                    }
                }

                if hasListeners {
                    sendEvent(withName: "onModelLoadProgress", body: [
                        "type": "tts",
                        "status": "downloading",
                        "progress": 0
                    ])
                }

                ttsManager = try await TtsManager(config: ttsConfig)

                if hasListeners {
                    sendEvent(withName: "onModelLoadProgress", body: [
                        "type": "tts",
                        "status": "ready",
                        "progress": 100
                    ])
                }

                resolve(["success": true])
            } catch {
                reject("TTS_INIT_ERROR", "Failed to initialize TTS: \(error.localizedDescription)", error)
            }
        }
        #else
        reject("TTS_NOT_AVAILABLE", "TTS module not included. Add FluidAudioTTS pod to enable.", nil)
        #endif
    }

    @objc(synthesize:voice:resolver:rejecter:)
    func synthesize(
        text: String,
        voice: String?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(FluidAudioTTS)
        Task {
            do {
                guard let tts = ttsManager else {
                    reject("TTS_NOT_INITIALIZED", "TTS manager not initialized. Call initializeTts first.", nil)
                    return
                }

                let voiceToUse = voice ?? TtsConstants.recommendedVoice
                let audioBuffer = try await tts.synthesize(text: text, voice: voiceToUse)

                // Convert AVAudioPCMBuffer to base64 data
                let base64Audio = audioBufferToBase64(audioBuffer)

                resolve([
                    "audioData": base64Audio,
                    "duration": Double(audioBuffer.frameLength) / audioBuffer.format.sampleRate,
                    "sampleRate": Int(audioBuffer.format.sampleRate)
                ])
            } catch {
                reject("TTS_SYNTHESIS_ERROR", "TTS synthesis failed: \(error.localizedDescription)", error)
            }
        }
        #else
        reject("TTS_NOT_AVAILABLE", "TTS module not included. Add FluidAudioTTS pod to enable.", nil)
        #endif
    }

    @objc(synthesizeToFile:voice:outputPath:resolver:rejecter:)
    func synthesizeToFile(
        text: String,
        voice: String?,
        outputPath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(FluidAudioTTS)
        Task {
            do {
                guard let tts = ttsManager else {
                    reject("TTS_NOT_INITIALIZED", "TTS manager not initialized. Call initializeTts first.", nil)
                    return
                }

                let voiceToUse = voice ?? TtsConstants.recommendedVoice
                let outputUrl = URL(fileURLWithPath: outputPath)

                try await tts.synthesizeAndWrite(text: text, to: outputUrl, voice: voiceToUse)

                resolve([
                    "success": true,
                    "outputPath": outputPath
                ])
            } catch {
                reject("TTS_SYNTHESIS_ERROR", "TTS synthesis failed: \(error.localizedDescription)", error)
            }
        }
        #else
        reject("TTS_NOT_AVAILABLE", "TTS module not included. Add FluidAudioTTS pod to enable.", nil)
        #endif
    }

    @objc(isTtsAvailable:rejecter:)
    func isTtsAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(FluidAudioTTS)
        Task {
            let available = await ttsManager?.isAvailable ?? false
            resolve(available)
        }
        #else
        resolve(false)
        #endif
    }

    // MARK: - Cleanup

    @objc(cleanup:rejecter:)
    func cleanup(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        streamingTask?.cancel()
        streamingTask = nil
        streamingAsrManager = nil
        asrManager = nil
        vadManager = nil
        diarizerManager?.cleanup()
        diarizerManager = nil
        #if canImport(FluidAudioTTS)
        ttsManager = nil
        #endif
        resolve(["success": true])
    }

    // MARK: - Helper Methods

    private func asrResultToDict(_ result: ASRResult) -> [String: Any] {
        var dict: [String: Any] = [
            "text": result.text,
            "confidence": result.confidence,
            "duration": result.duration,
            "processingTime": result.processingTime,
            "rtfx": result.rtfx
        ]

        if let tokenTimings = result.tokenTimings {
            dict["tokenTimings"] = tokenTimings.map { timing -> [String: Any] in
                [
                    "token": timing.token,
                    "tokenId": timing.tokenId,
                    "startTime": timing.startTime,
                    "endTime": timing.endTime,
                    "confidence": timing.confidence
                ]
            }
        }

        if let metrics = result.performanceMetrics {
            dict["performanceMetrics"] = [
                "preprocessDuration": metrics.preprocessDuration,
                "encoderDuration": metrics.encoderDuration,
                "decoderDuration": metrics.decoderDuration
            ]
        }

        return dict
    }

    private func diarizationResultToDict(_ result: DiarizationResult) -> [String: Any] {
        var dict: [String: Any] = [
            "segments": result.segments.map { segment -> [String: Any] in
                [
                    "id": segment.id.uuidString,
                    "speakerId": segment.speakerId,
                    "startTime": segment.startTimeSeconds,
                    "endTime": segment.endTimeSeconds,
                    "duration": segment.durationSeconds,
                    "qualityScore": segment.qualityScore,
                    "embedding": segment.embedding
                ]
            }
        ]

        if let speakerDatabase = result.speakerDatabase {
            dict["speakerDatabase"] = speakerDatabase
        }

        if let timings = result.timings {
            dict["timings"] = [
                "total": timings.totalDuration,
                "segmentation": timings.segmentationDuration,
                "embedding": timings.embeddingDuration,
                "clustering": timings.clusteringDuration
            ]
        }

        return dict
    }

    private func audioDataToFloatSamples(_ data: Data) -> [Float] {
        // Assuming 16-bit PCM audio
        let count = data.count / 2
        var samples = [Float](repeating: 0, count: count)

        data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<count {
                samples[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }

        return samples
    }

    private func dataToAudioBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let frameCount = UInt32(data.count / 2) // 16-bit audio

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<Int(frameCount) {
                floatChannelData[0][i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }

        return buffer
    }

    private func audioBufferToBase64(_ buffer: AVAudioPCMBuffer) -> String {
        guard let floatChannelData = buffer.floatChannelData else {
            return ""
        }

        let frameCount = Int(buffer.frameLength)
        var int16Data = [Int16](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let sample = floatChannelData[0][i]
            let clamped = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(clamped * Float(Int16.max))
        }

        let data = int16Data.withUnsafeBytes { Data($0) }
        return data.base64EncodedString()
    }
}
