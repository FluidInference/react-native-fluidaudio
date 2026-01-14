import Foundation
import AVFoundation
import FluidAudio

#if canImport(FluidAudioTTS)
import FluidAudioTTS
private let ttsAvailable = true
#else
private let ttsAvailable = false
#endif

/// Swift implementation of FluidAudio functionality
/// Called from both legacy bridge and TurboModule
@objc public class FluidAudioImpl: NSObject {

    // MARK: - Properties

    private var asrManager: AsrManager?
    private var streamingAsrManager: StreamingAsrManager?
    private var vadManager: VadManager?
    private var diarizerManager: DiarizerManager?
    #if canImport(FluidAudioTTS)
    private var ttsManager: TtsManager?
    #endif
    private var audioConverter: AudioConverter?
    private var streamingTask: Task<Void, Never>?

    // MARK: - Initialization

    @objc public override init() {
        super.init()
        audioConverter = AudioConverter()
    }

    // MARK: - System Info

    @objc public func getSystemInfo(
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

    // MARK: - ASR

    @objc public func initializeAsr(
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
                let models = try await AsrModels.downloadAndLoad()
                try await asrManager?.initialize(models: models)

                resolve([
                    "success": true,
                    "compilationDuration": models.compilationDuration
                ])
            } catch {
                reject("ASR_INIT_ERROR", "Failed to initialize ASR: \(error.localizedDescription)", error)
            }
        }
    }

    @objc public func transcribeFile(
        filePath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                guard let asr = asrManager else {
                    reject("ASR_NOT_INITIALIZED", "ASR manager not initialized", nil)
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

    /// Zero-copy transcription from raw float samples
    @objc public func transcribeAudioData(
        data: Data,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                guard let asr = asrManager else {
                    reject("ASR_NOT_INITIALIZED", "ASR manager not initialized", nil)
                    return
                }

                let samples = dataToFloatSamples(data)

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

    @objc public func isAsrAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(asrManager?.isAvailable ?? false)
    }

    // MARK: - Streaming ASR

    @objc public func startStreamingAsr(
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

                resolve(["success": true])
            } catch {
                reject("STREAMING_START_ERROR", "Failed to start streaming: \(error.localizedDescription)", error)
            }
        }
    }

    /// Zero-copy streaming audio feed
    @objc public func feedStreamingAudio(data: Data) {
        guard let manager = streamingAsrManager else { return }

        let samples = dataToFloatSamples(data)
        guard let buffer = samplesToAudioBuffer(samples) else { return }

        Task {
            await manager.streamAudio(buffer)
        }
    }

    @objc public func stopStreamingAsr(
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

                resolve([
                    "text": finalText,
                    "success": true
                ])
            } catch {
                reject("STREAMING_STOP_ERROR", "Failed to stop streaming: \(error.localizedDescription)", error)
            }
        }
    }

    // MARK: - VAD

    @objc public func initializeVad(
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

    @objc public func processVadFile(
        filePath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                guard let vad = vadManager else {
                    reject("VAD_NOT_INITIALIZED", "VAD manager not initialized", nil)
                    return
                }

                let url = URL(fileURLWithPath: filePath)
                let results = try await vad.process(url)
                resolve(vadResultsToDict(results))
            } catch {
                reject("VAD_PROCESS_ERROR", "VAD processing failed: \(error.localizedDescription)", error)
            }
        }
    }

    /// Zero-copy VAD processing
    @objc public func processVadAudioData(
        data: Data,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                guard let vad = vadManager else {
                    reject("VAD_NOT_INITIALIZED", "VAD manager not initialized", nil)
                    return
                }

                let samples = dataToFloatSamples(data)
                let results = try await vad.process(samples)
                resolve(vadResultsToDict(results))
            } catch {
                reject("VAD_PROCESS_ERROR", "VAD processing failed: \(error.localizedDescription)", error)
            }
        }
    }

    @objc public func isVadAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            let available = await vadManager?.isAvailable ?? false
            resolve(available)
        }
    }

    // MARK: - Diarization

    @objc public func initializeDiarization(
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
                let models = try await DiarizerModels.downloadIfNeeded()
                diarizerManager?.initialize(models: models)

                resolve([
                    "success": true,
                    "compilationDuration": models.compilationDuration
                ])
            } catch {
                reject("DIARIZATION_INIT_ERROR", "Failed to initialize diarization: \(error.localizedDescription)", error)
            }
        }
    }

    @objc public func performDiarizationFile(
        filePath: String,
        sampleRate: Double,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                guard let diarizer = diarizerManager,
                      let converter = audioConverter else {
                    reject("DIARIZATION_NOT_INITIALIZED", "Diarization manager not initialized", nil)
                    return
                }

                let url = URL(fileURLWithPath: filePath)
                let samples = try converter.resampleAudioFile(url)
                let result = try diarizer.performCompleteDiarization(samples, sampleRate: 16000)

                resolve(diarizationResultToDict(result))
            } catch {
                reject("DIARIZATION_ERROR", "Diarization failed: \(error.localizedDescription)", error)
            }
        }
    }

    /// Zero-copy diarization
    @objc public func performDiarizationAudioData(
        data: Data,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        Task {
            do {
                guard let diarizer = diarizerManager else {
                    reject("DIARIZATION_NOT_INITIALIZED", "Diarization manager not initialized", nil)
                    return
                }

                var samples = dataToFloatSamples(data)

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

    @objc public func initializeKnownSpeakers(
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

            let speaker = Speaker(id: id, name: name, currentEmbedding: embedding)
            speakerObjects.append(speaker)
        }

        diarizer.initializeKnownSpeakers(speakerObjects)
        resolve(["success": true, "speakerCount": speakerObjects.count])
    }

    @objc public func isDiarizationAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(diarizerManager?.isAvailable ?? false)
    }

    // MARK: - TTS

    @objc public func initializeTts(
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

                ttsManager = try await TtsManager(config: ttsConfig)
                resolve(["success": true])
            } catch {
                reject("TTS_INIT_ERROR", "Failed to initialize TTS: \(error.localizedDescription)", error)
            }
        }
        #else
        reject("TTS_NOT_AVAILABLE", "TTS module not included", nil)
        #endif
    }

    /// Zero-copy TTS synthesis - returns raw audio data
    @objc public func synthesize(
        text: String,
        voice: String?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(FluidAudioTTS)
        Task {
            do {
                guard let tts = ttsManager else {
                    reject("TTS_NOT_INITIALIZED", "TTS manager not initialized", nil)
                    return
                }

                let voiceToUse = voice ?? TtsConstants.recommendedVoice
                let audioBuffer = try await tts.synthesize(text: text, voice: voiceToUse)

                // Convert to raw data for JSI
                let audioData = audioBufferToData(audioBuffer)

                resolve([
                    "audioData": audioData,
                    "duration": Double(audioBuffer.frameLength) / audioBuffer.format.sampleRate,
                    "sampleRate": Int(audioBuffer.format.sampleRate)
                ])
            } catch {
                reject("TTS_SYNTHESIS_ERROR", "TTS synthesis failed: \(error.localizedDescription)", error)
            }
        }
        #else
        reject("TTS_NOT_AVAILABLE", "TTS module not included", nil)
        #endif
    }

    @objc public func synthesizeToFile(
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
                    reject("TTS_NOT_INITIALIZED", "TTS manager not initialized", nil)
                    return
                }

                let voiceToUse = voice ?? TtsConstants.recommendedVoice
                let outputUrl = URL(fileURLWithPath: outputPath)
                try await tts.synthesizeAndWrite(text: text, to: outputUrl, voice: voiceToUse)

                resolve(["success": true, "outputPath": outputPath])
            } catch {
                reject("TTS_SYNTHESIS_ERROR", "TTS synthesis failed: \(error.localizedDescription)", error)
            }
        }
        #else
        reject("TTS_NOT_AVAILABLE", "TTS module not included", nil)
        #endif
    }

    @objc public func isTtsAvailable(
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

    @objc public func cleanup(
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

    private func dataToFloatSamples(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: count)

        data.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<count {
                samples[i] = floatBuffer[i]
            }
        }

        return samples
    }

    private func samplesToAudioBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let frameCount = UInt32(samples.count)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        for i in 0..<Int(frameCount) {
            floatChannelData[0][i] = samples[i]
        }

        return buffer
    }

    private func audioBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatChannelData = buffer.floatChannelData else {
            return Data()
        }

        let frameCount = Int(buffer.frameLength)
        var data = Data(count: frameCount * MemoryLayout<Float>.size)

        data.withUnsafeMutableBytes { rawBuffer in
            let destBuffer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<frameCount {
                destBuffer[i] = floatChannelData[0][i]
            }
        }

        return data
    }

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

    private func vadResultsToDict(_ results: [VadResult]) -> [String: Any] {
        let resultDicts = results.map { result -> [String: Any] in
            [
                "chunkIndex": result.chunkIndex,
                "probability": result.probability,
                "isActive": result.isActive,
                "processingTime": result.processingTime
            ]
        }

        return [
            "results": resultDicts,
            "chunkSize": VadManager.chunkSize,
            "sampleRate": VadManager.sampleRate
        ]
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
}
