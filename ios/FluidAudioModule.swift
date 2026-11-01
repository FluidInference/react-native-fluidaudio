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

    /// Decode little-endian 16-bit PCM into Float samples in [-1, 1).
    /// Base64-decoded `Data` has no alignment guarantee, so read each sample unaligned.
    static func int16LEToFloat(_ data: Data) -> [Float] {
        let count = data.count / 2
        return data.withUnsafeBytes { raw -> [Float] in
            (0..<count).map { index in
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                return Float(sample) / 32768.0
            }
        }
    }

    /// Wrap little-endian 16-bit mono PCM in a Float32 buffer at `sampleRate`.
    static func pcm16MonoBuffer(from data: Data, sampleRate: Double) -> AVAudioPCMBuffer? {
        let samples = int16LEToFloat(data)
        guard !samples.isEmpty,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    /// Copy a tap buffer: the engine reuses it once the tap block returns.
    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}

/// Where a streaming session's audio comes from.
enum StreamingSource: String {
    /// The module captures the microphone itself.
    case microphone
    /// The app feeds audio through `feedStreamingAudio`.
    case manual
}

/// One streaming session: audio from the microphone tap or `feedStreamingAudio` goes through
/// `audio` in order, and `processing` hands it to the manager one buffer at a time.
final class StreamingSession {
    let manager: any StreamingAsrManager
    let variant: StreamingModelVariant
    let source: StreamingSource
    let audio: AsyncStream<AVAudioPCMBuffer>.Continuation
    let processing: Task<Void, Never>
    var engine: AVAudioEngine?

    init(
        manager: any StreamingAsrManager,
        variant: StreamingModelVariant,
        source: StreamingSource,
        audio: AsyncStream<AVAudioPCMBuffer>.Continuation,
        processing: Task<Void, Never>
    ) {
        self.manager = manager
        self.variant = variant
        self.source = source
        self.audio = audio
        self.processing = processing
    }

    func stopMicrophone() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@objc(FluidAudioModule)
class FluidAudioModule: RCTEventEmitter {

    private var hasListeners = false

    // Streaming ASR. `streamingLock` guards both properties: React Native calls
    // module methods on its own queue while sessions start and stop in Tasks.
    private let streamingLock = NSLock()
    private var streamingSession: StreamingSession?
    /// Set from `startStreamingAsr` until its session is ready, so a second start is refused.
    private var streamingStarting = false
    /// The last streaming manager used, kept loaded so the next session with the
    /// same model starts without reloading it.
    private var idleStreamingManager: (variant: StreamingModelVariant, manager: any StreamingAsrManager)?

    static let defaultStreamingModel = StreamingModelVariant.parakeetEou320ms

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
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                self.asrModels = models

                sendEvent(name: "onModelLoadProgress", body: [
                    "type": "asr",
                    "status": "compiling",
                    "progress": 50
                ])

                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
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
                var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
                let result = try await asrManager.transcribe(url, decoderState: &decoderState)

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
                let samples = AudioUtils.int16LEToFloat(audioData)
                var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
                let result = try await asrManager.transcribe(samples, decoderState: &decoderState)

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

    private func withStreamingLock<T>(_ body: () throws -> T) rethrows -> T {
        streamingLock.lock()
        defer { streamingLock.unlock() }
        return try body()
    }

    /// Reuse the idle manager for `variant`, or create and load a new one.
    private func streamingManager(for variant: StreamingModelVariant) async throws -> any StreamingAsrManager {
        let idle = withStreamingLock { () -> (variant: StreamingModelVariant, manager: any StreamingAsrManager)? in
            defer { idleStreamingManager = nil }
            return idleStreamingManager
        }
        if let idle {
            if idle.variant == variant {
                try await idle.manager.reset()
                return idle.manager
            }
            await idle.manager.cleanup()
        }

        sendEvent(name: "onModelLoadProgress", body: [
            "type": "streaming",
            "status": "downloading",
            "progress": 0
        ])
        let manager = variant.createManager()
        try await manager.loadModels()
        sendEvent(name: "onModelLoadProgress", body: [
            "type": "streaming",
            "status": "ready",
            "progress": 100
        ])
        return manager
    }

    /// Start capturing the microphone into the session's audio queue.
    private func startMicrophone(into audio: AsyncStream<AVAudioPCMBuffer>.Continuation) throws -> AVAudioEngine {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            // The streaming manager resamples to 16 kHz mono itself.
            if let copy = AudioUtils.copy(buffer) {
                audio.yield(copy)
            }
        }
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
        return engine
    }

    /// Start a streaming session.
    ///
    /// Config:
    /// - `source`: `"microphone"` (default) captures the microphone; `"manual"` takes audio
    ///   only from `feedStreamingAudio`.
    /// - `model`: a `StreamingModelVariant` raw value; defaults to `"parakeet-eou-320ms"`.
    @objc(startStreamingAsr:resolver:rejecter:)
    func startStreamingAsr(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let sourceName = config?["source"] as? String ?? StreamingSource.microphone.rawValue
        guard let source = StreamingSource(rawValue: sourceName) else {
            reject(
                "STREAMING_SOURCE_UNSUPPORTED",
                "Unsupported streaming source '\(sourceName)'. Use 'microphone' or 'manual'.", nil)
            return
        }
        let modelName = config?["model"] as? String ?? Self.defaultStreamingModel.rawValue
        guard let variant = StreamingModelVariant(rawValue: modelName) else {
            let known = StreamingModelVariant.allCases.map(\.rawValue).joined(separator: ", ")
            reject("STREAMING_MODEL_UNSUPPORTED", "Unknown streaming model '\(modelName)'. Use one of: \(known).", nil)
            return
        }

        let alreadyActive = withStreamingLock { () -> Bool in
            if streamingSession != nil || streamingStarting { return true }
            streamingStarting = true
            return false
        }
        guard !alreadyActive else {
            reject("STREAMING_ACTIVE", "Streaming is already active", nil)
            return
        }

        Task { [weak self] in
            guard let self else {
                reject("STREAMING_START_ERROR", "The FluidAudio module was released", nil)
                return
            }
            var loadedManager: (any StreamingAsrManager)?
            var startedSession: StreamingSession?
            do {
                let manager = try await streamingManager(for: variant)
                loadedManager = manager
                await manager.setPartialTranscriptCallback { [weak self] text in
                    // These models never revise emitted text, so the partial transcript is confirmed.
                    self?.sendEvent(name: "onStreamingUpdate", body: [
                        "volatile": "",
                        "confirmed": text,
                        "text": text,
                        "isFinal": false
                    ])
                }

                let (stream, audio) = AsyncStream<AVAudioPCMBuffer>.makeStream()
                let processing = Task { [weak self] in
                    for await buffer in stream {
                        do {
                            try await manager.appendAudio(buffer)
                            try await manager.processBufferedAudio()
                        } catch {
                            self?.sendEvent(name: "onTranscriptionError", body: [
                                "code": "STREAMING_PROCESS_ERROR",
                                "message": error.localizedDescription
                            ])
                        }
                    }
                }
                let session = StreamingSession(
                    manager: manager, variant: variant, source: source, audio: audio, processing: processing)
                startedSession = session

                if source == .microphone {
                    session.engine = try startMicrophone(into: audio)
                }

                withStreamingLock {
                    self.streamingSession = session
                    self.streamingStarting = false
                }
                resolve(["success": true, "source": source.rawValue, "model": variant.rawValue])
            } catch {
                if let startedSession {
                    startedSession.stopMicrophone()
                    startedSession.audio.finish()
                }
                if source == .microphone {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
                withStreamingLock {
                    if let loadedManager { self.idleStreamingManager = (variant, loadedManager) }
                    self.streamingStarting = false
                }
                reject("STREAMING_START_ERROR", "Failed to start streaming: \(error.localizedDescription)", error)
            }
        }
    }

    /// Feed audio to a session started with `source: 'manual'`.
    ///
    /// `base64Audio` is little-endian 16-bit mono PCM at 16 kHz. The buffer is queued in order
    /// behind any audio already fed; transcript updates arrive as `onStreamingUpdate` events.
    @objc(feedStreamingAudio:resolver:rejecter:)
    func feedStreamingAudio(
        base64Audio: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let session = withStreamingLock({ streamingSession }) else {
            reject("STREAMING_NOT_ACTIVE", "Streaming not started. Call startStreamingAsr first.", nil)
            return
        }
        guard session.source == .manual else {
            reject(
                "STREAMING_SOURCE_MICROPHONE",
                "This session captures the microphone itself. Start streaming with source: 'manual' to feed audio.",
                nil)
            return
        }
        guard let audioData = Data(base64Encoded: base64Audio) else {
            reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
            return
        }
        guard audioData.count % 2 == 0 else {
            reject("INVALID_AUDIO", "Audio must be 16-bit PCM, but has an odd number of bytes", nil)
            return
        }
        guard let buffer = AudioUtils.pcm16MonoBuffer(from: audioData, sampleRate: 16000) else {
            reject("INVALID_AUDIO", "Audio data is empty", nil)
            return
        }

        session.audio.yield(buffer)
        resolve(["success": true, "samples": Int(buffer.frameLength)])
    }

    /// Stop the session: transcribe all audio queued so far, then return the final text.
    @objc(stopStreamingAsr:rejecter:)
    func stopStreamingAsr(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let session = withStreamingLock({ () -> StreamingSession? in
            defer { streamingSession = nil }
            return streamingSession
        }) else {
            resolve(["text": "", "success": true])
            return
        }

        Task {
            session.stopMicrophone()
            session.audio.finish()
            await session.processing.value

            do {
                let finalText = try await session.manager.finish()
                sendEvent(name: "onStreamingUpdate", body: [
                    "volatile": "",
                    "confirmed": finalText,
                    "text": finalText,
                    "isFinal": true
                ])
                withStreamingLock { idleStreamingManager = (session.variant, session.manager) }
                resolve([
                    "text": finalText,
                    "success": true
                ])
            } catch {
                await session.manager.cleanup()
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
                let samples = AudioUtils.int16LEToFloat(audioData)

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
                let samples = AudioUtils.int16LEToFloat(audioData)

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
        let (session, idle) = withStreamingLock {
            () -> (StreamingSession?, (variant: StreamingModelVariant, manager: any StreamingAsrManager)?) in
            defer {
                streamingSession = nil
                idleStreamingManager = nil
            }
            return (streamingSession, idleStreamingManager)
        }

        Task {
            // Stop streaming if active, discarding queued audio
            if let session {
                session.stopMicrophone()
                session.audio.finish()
                session.processing.cancel()
                await session.manager.cleanup()
            }
            if let idle {
                await idle.manager.cleanup()
            }

            // Clean up managers
            await asrManager?.cleanup()
            asrManager = nil
            asrModels = nil
            vadManager = nil
            diarizerManager = nil

            resolve(["success": true])
        }
    }
}
