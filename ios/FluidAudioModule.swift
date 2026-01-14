import Foundation
import React
import AVFoundation
import FluidAudio

@objc(FluidAudioModule)
class FluidAudioModule: RCTEventEmitter {

    private var hasListeners = false

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

    // MARK: - System Info

    @objc(getSystemInfo:rejecter:)
    func getSystemInfo(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // Check architecture at compile time
        #if arch(arm64)
        let isAppleSilicon = true
        let isIntelMac = false
        #elseif arch(x86_64)
        let isAppleSilicon = false
        let isIntelMac = true
        #else
        let isAppleSilicon = false
        let isIntelMac = false
        #endif

        let info: [String: Any] = [
            "isAppleSilicon": isAppleSilicon,
            "isIntelMac": isIntelMac,
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
        // TODO: Implement actual ASR initialization with FluidAudio
        resolve([
            "success": true,
            "message": "ASR module ready (stub)"
        ])
    }

    @objc(transcribeFile:resolver:rejecter:)
    func transcribeFile(
        filePath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // TODO: Implement actual file transcription with FluidAudio
        resolve([
            "text": "Transcription not yet implemented",
            "duration": 0.0,
            "segments": []
        ])
    }

    @objc(transcribeAudioData:sampleRate:resolver:rejecter:)
    func transcribeAudioData(
        base64Audio: String,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // TODO: Implement actual audio transcription with FluidAudio
        resolve([
            "text": "Transcription not yet implemented",
            "duration": 0.0,
            "segments": []
        ])
    }

    @objc(isAsrAvailable:rejecter:)
    func isAsrAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(true)
    }

    // MARK: - Streaming ASR

    @objc(startStreamingAsr:resolver:rejecter:)
    func startStreamingAsr(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(nil)
    }

    @objc(feedStreamingAudio:resolver:rejecter:)
    func feedStreamingAudio(
        base64Audio: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(nil)
    }

    @objc(stopStreamingAsr:rejecter:)
    func stopStreamingAsr(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "finalText": "",
            "totalDuration": 0.0
        ])
    }

    // MARK: - VAD (Voice Activity Detection)

    @objc(initializeVad:resolver:rejecter:)
    func initializeVad(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(nil)
    }

    @objc(processVad:resolver:rejecter:)
    func processVad(
        filePath: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "results": [],
            "chunkSize": 512,
            "sampleRate": 16000
        ])
    }

    @objc(processVadAudioData:resolver:rejecter:)
    func processVadAudioData(
        base64Audio: String,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "results": [],
            "chunkSize": 512,
            "sampleRate": 16000
        ])
    }

    @objc(isVadAvailable:rejecter:)
    func isVadAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(true)
    }

    // MARK: - Diarization

    @objc(initializeDiarization:resolver:rejecter:)
    func initializeDiarization(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "success": true,
            "message": "Diarization ready (stub)"
        ])
    }

    @objc(performDiarization:sampleRate:resolver:rejecter:)
    func performDiarization(
        filePath: String,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "segments": [],
            "speakerCount": 0
        ])
    }

    @objc(performDiarizationOnAudioData:sampleRate:resolver:rejecter:)
    func performDiarizationOnAudioData(
        base64Audio: String,
        sampleRate: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "segments": [],
            "speakerCount": 0
        ])
    }

    @objc(initializeKnownSpeakers:resolver:rejecter:)
    func initializeKnownSpeakers(
        speakers: NSArray,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve([
            "speakerCount": speakers.count
        ])
    }

    @objc(isDiarizationAvailable:rejecter:)
    func isDiarizationAvailable(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(true)
    }

    // MARK: - TTS (Text-to-Speech)

    @objc(initializeTts:resolver:rejecter:)
    func initializeTts(
        config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(nil)
    }

    @objc(synthesize:voice:resolver:rejecter:)
    func synthesize(
        text: String,
        voice: String?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
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
        resolve(nil)
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
        resolve(nil)
    }
}
