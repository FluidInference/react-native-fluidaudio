import { NativeModules, NativeEventEmitter, Platform } from 'react-native';
import type {
  SystemInfo,
  ASRConfig,
  ASRResult,
  ASRInitResult,
  StreamingASRConfig,
  StreamingUpdate,
  StreamingStopResult,
  VADConfig,
  VADResult,
  DiarizationConfig,
  DiarizationResult,
  DiarizationInitResult,
  KnownSpeaker,
  ModelLoadProgressEvent,
  TTSConfig,
  TTSResult,
  FluidAudioNativeModule,
} from './types';

const LINKING_ERROR =
  `The package 'react-native-fluidaudio' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go (Expo does not support native modules)\n';

// Try TurboModule first (New Architecture), fallback to legacy bridge
const FluidAudioNative: FluidAudioNativeModule = (() => {
  // Check for TurboModule (New Architecture)
  if (global.__turboModuleProxy) {
    try {
      const turboModule = require('./NativeFluidAudio').default;
      if (turboModule) return turboModule;
    } catch {}
  }

  // Fallback to legacy bridge
  return NativeModules.FluidAudioModule
    ? NativeModules.FluidAudioModule
    : new Proxy(
        {},
        {
          get() {
            throw new Error(LINKING_ERROR);
          },
        }
      );
})();

const eventEmitter = new NativeEventEmitter(
  NativeModules.FluidAudioModule ?? FluidAudioNative
);

/**
 * Check if JSI bindings are available (New Architecture with zero-copy)
 */
function hasJSI(): boolean {
  return (
    typeof global !== 'undefined' &&
    typeof (global as any).FluidAudio_transcribeAudioBuffer === 'function'
  );
}

/**
 * Check if using New Architecture (TurboModules)
 */
export function isNewArchitecture(): boolean {
  return !!global.__turboModuleProxy;
}

/**
 * Check if zero-copy JSI is available
 */
export function hasZeroCopySupport(): boolean {
  return hasJSI();
}

// ============================================================================
// Event Subscription Helpers
// ============================================================================

type StreamingUpdateHandler = (update: StreamingUpdate) => void;
type ModelLoadProgressHandler = (event: ModelLoadProgressEvent) => void;
type ErrorHandler = (error: { code: string; message: string }) => void;

export interface EventSubscription {
  remove: () => void;
}

/**
 * Subscribe to streaming transcription updates
 */
export function onStreamingUpdate(handler: StreamingUpdateHandler): EventSubscription {
  const subscription = eventEmitter.addListener('onStreamingUpdate', handler);
  return { remove: () => subscription.remove() };
}

/**
 * Subscribe to model loading progress events
 */
export function onModelLoadProgress(handler: ModelLoadProgressHandler): EventSubscription {
  const subscription = eventEmitter.addListener('onModelLoadProgress', handler);
  return { remove: () => subscription.remove() };
}

/**
 * Subscribe to transcription errors
 */
export function onTranscriptionError(handler: ErrorHandler): EventSubscription {
  const subscription = eventEmitter.addListener('onTranscriptionError', handler);
  return { remove: () => subscription.remove() };
}

// ============================================================================
// System Info
// ============================================================================

/**
 * Get system information including Apple Silicon detection
 */
export async function getSystemInfo(): Promise<SystemInfo> {
  return FluidAudioNative.getSystemInfo();
}

/**
 * Check if running on Apple Silicon (required for most ML models)
 */
export async function isAppleSilicon(): Promise<boolean> {
  const info = await getSystemInfo();
  return info.isAppleSilicon;
}

// ============================================================================
// ASR (Automatic Speech Recognition)
// ============================================================================

/**
 * ASR Manager for speech-to-text transcription
 *
 * Supports both legacy bridge (base64) and JSI (zero-copy ArrayBuffer)
 */
export class ASRManager {
  private initialized = false;

  /**
   * Initialize the ASR manager and download/compile models
   * Note: First initialization may take 20-30 seconds for model compilation
   */
  async initialize(config?: ASRConfig): Promise<ASRInitResult> {
    const result = await FluidAudioNative.initializeAsr(config);
    this.initialized = result.success;
    return result;
  }

  /**
   * Transcribe an audio file
   * @param filePath Absolute path to the audio file
   */
  async transcribeFile(filePath: string): Promise<ASRResult> {
    this.ensureInitialized();
    return FluidAudioNative.transcribeFile(filePath);
  }

  /**
   * Transcribe audio from ArrayBuffer (zero-copy with JSI when available)
   * @param audioBuffer ArrayBuffer containing 16-bit PCM audio
   * @param sampleRate Sample rate of the audio (will be resampled to 16kHz)
   */
  async transcribeBuffer(audioBuffer: ArrayBuffer, sampleRate: number = 16000): Promise<ASRResult> {
    this.ensureInitialized();

    if (hasJSI()) {
      // Zero-copy path via JSI
      return (global as any).FluidAudio_transcribeAudioBuffer(audioBuffer, sampleRate);
    } else {
      // Legacy path: convert to base64
      const base64 = arrayBufferToBase64(audioBuffer);
      return FluidAudioNative.transcribeAudioData(base64, sampleRate);
    }
  }

  /**
   * Transcribe raw audio data (legacy base64 API)
   * @deprecated Use transcribeBuffer() for better performance
   * @param base64Audio Base64-encoded 16-bit PCM audio
   * @param sampleRate Sample rate of the audio (will be resampled to 16kHz)
   */
  async transcribe(base64Audio: string, sampleRate: number = 16000): Promise<ASRResult> {
    this.ensureInitialized();
    return FluidAudioNative.transcribeAudioData(base64Audio, sampleRate);
  }

  /**
   * Check if ASR is available and ready
   */
  async isAvailable(): Promise<boolean> {
    return FluidAudioNative.isAsrAvailable();
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error('ASR not initialized. Call initialize() first.');
    }
  }
}

// ============================================================================
// Streaming ASR
// ============================================================================

/**
 * Streaming ASR Manager for real-time transcription
 *
 * Supports both legacy bridge (base64) and JSI (zero-copy ArrayBuffer)
 */
export class StreamingASRManager {
  private streaming = false;
  private updateSubscription: EventSubscription | null = null;

  /**
   * Start streaming transcription
   * @param config Streaming configuration
   * @param onUpdate Callback for transcription updates
   */
  async start(config?: StreamingASRConfig, onUpdate?: StreamingUpdateHandler): Promise<void> {
    if (this.streaming) {
      throw new Error('Streaming already in progress. Call stop() first.');
    }

    if (onUpdate) {
      this.updateSubscription = onStreamingUpdate(onUpdate);
    }

    await FluidAudioNative.startStreamingAsr(config);
    this.streaming = true;
  }

  /**
   * Feed audio data using ArrayBuffer (zero-copy with JSI when available)
   * @param audioBuffer ArrayBuffer containing 16-bit PCM audio at 16kHz
   */
  async feedBuffer(audioBuffer: ArrayBuffer): Promise<void> {
    if (!this.streaming) {
      throw new Error('Streaming not started. Call start() first.');
    }

    if (hasJSI()) {
      // Zero-copy synchronous path via JSI
      (global as any).FluidAudio_feedStreamingAudioBuffer(audioBuffer);
    } else {
      // Legacy path: convert to base64
      const base64 = arrayBufferToBase64(audioBuffer);
      await FluidAudioNative.feedStreamingAudio(base64);
    }
  }

  /**
   * Feed audio data (legacy base64 API)
   * @deprecated Use feedBuffer() for better performance
   * @param base64Audio Base64-encoded 16-bit PCM audio at 16kHz
   */
  async feedAudio(base64Audio: string): Promise<void> {
    if (!this.streaming) {
      throw new Error('Streaming not started. Call start() first.');
    }
    await FluidAudioNative.feedStreamingAudio(base64Audio);
  }

  /**
   * Stop streaming and get final transcription
   */
  async stop(): Promise<StreamingStopResult> {
    this.updateSubscription?.remove();
    this.updateSubscription = null;

    const result = await FluidAudioNative.stopStreamingAsr();
    this.streaming = false;
    return result;
  }

  /**
   * Check if streaming is currently active
   */
  isStreaming(): boolean {
    return this.streaming;
  }
}

// ============================================================================
// VAD (Voice Activity Detection)
// ============================================================================

/**
 * VAD Manager for voice activity detection
 *
 * Supports both legacy bridge (base64) and JSI (zero-copy ArrayBuffer)
 */
export class VADManager {
  private initialized = false;

  /**
   * Initialize the VAD manager
   */
  async initialize(config?: VADConfig): Promise<void> {
    await FluidAudioNative.initializeVad(config);
    this.initialized = true;
  }

  /**
   * Process an audio file for voice activity
   * @param filePath Absolute path to the audio file
   */
  async processFile(filePath: string): Promise<VADResult> {
    this.ensureInitialized();
    return FluidAudioNative.processVad(filePath);
  }

  /**
   * Process audio buffer for voice activity (zero-copy with JSI when available)
   * @param audioBuffer ArrayBuffer containing 16-bit PCM audio at 16kHz
   */
  async processBuffer(audioBuffer: ArrayBuffer): Promise<VADResult> {
    this.ensureInitialized();

    if (hasJSI()) {
      return (global as any).FluidAudio_processVadBuffer(audioBuffer);
    } else {
      const base64 = arrayBufferToBase64(audioBuffer);
      return FluidAudioNative.processVadAudioData(base64);
    }
  }

  /**
   * Process raw audio data for voice activity (legacy base64 API)
   * @deprecated Use processBuffer() for better performance
   * @param base64Audio Base64-encoded 16-bit PCM audio at 16kHz
   */
  async process(base64Audio: string): Promise<VADResult> {
    this.ensureInitialized();
    return FluidAudioNative.processVadAudioData(base64Audio);
  }

  /**
   * Check if VAD is available and ready
   */
  async isAvailable(): Promise<boolean> {
    return FluidAudioNative.isVadAvailable();
  }

  /**
   * Get speech segments from VAD results
   * @param vadResult VAD processing result
   * @returns Array of speech segments with start/end times
   */
  getSpeechSegments(vadResult: VADResult): Array<{ start: number; end: number }> {
    const segments: Array<{ start: number; end: number }> = [];
    let segmentStart: number | null = null;

    const chunkDuration = vadResult.chunkSize / vadResult.sampleRate;

    for (const chunk of vadResult.results) {
      const chunkTime = chunk.chunkIndex * chunkDuration;

      if (chunk.isActive && segmentStart === null) {
        segmentStart = chunkTime;
      } else if (!chunk.isActive && segmentStart !== null) {
        segments.push({ start: segmentStart, end: chunkTime });
        segmentStart = null;
      }
    }

    // Handle trailing speech segment
    if (segmentStart !== null) {
      const lastChunk = vadResult.results[vadResult.results.length - 1];
      if (lastChunk) {
        segments.push({
          start: segmentStart,
          end: (lastChunk.chunkIndex + 1) * chunkDuration,
        });
      }
    }

    return segments;
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error('VAD not initialized. Call initialize() first.');
    }
  }
}

// ============================================================================
// Diarization (Speaker Identification)
// ============================================================================

/**
 * Diarization Manager for speaker identification
 *
 * Supports both legacy bridge (base64) and JSI (zero-copy ArrayBuffer)
 */
export class DiarizationManager {
  private initialized = false;

  /**
   * Initialize the Diarization manager and download/compile models
   */
  async initialize(config?: DiarizationConfig): Promise<DiarizationInitResult> {
    const result = await FluidAudioNative.initializeDiarization(config);
    this.initialized = result.success;
    return result;
  }

  /**
   * Perform speaker diarization on an audio file
   * @param filePath Absolute path to the audio file
   * @param sampleRate Sample rate of the audio (will be resampled to 16kHz)
   */
  async diarizeFile(filePath: string, sampleRate: number = 16000): Promise<DiarizationResult> {
    this.ensureInitialized();
    return FluidAudioNative.performDiarization(filePath, sampleRate);
  }

  /**
   * Diarize audio buffer (zero-copy with JSI when available)
   * @param audioBuffer ArrayBuffer containing 16-bit PCM audio
   * @param sampleRate Sample rate of the audio (will be resampled to 16kHz)
   */
  async diarizeBuffer(audioBuffer: ArrayBuffer, sampleRate: number = 16000): Promise<DiarizationResult> {
    this.ensureInitialized();

    if (hasJSI()) {
      return (global as any).FluidAudio_performDiarizationBuffer(audioBuffer, sampleRate);
    } else {
      const base64 = arrayBufferToBase64(audioBuffer);
      return FluidAudioNative.performDiarizationOnAudioData(base64, sampleRate);
    }
  }

  /**
   * Perform speaker diarization on raw audio data (legacy base64 API)
   * @deprecated Use diarizeBuffer() for better performance
   * @param base64Audio Base64-encoded 16-bit PCM audio
   * @param sampleRate Sample rate of the audio (will be resampled to 16kHz)
   */
  async diarize(base64Audio: string, sampleRate: number = 16000): Promise<DiarizationResult> {
    this.ensureInitialized();
    return FluidAudioNative.performDiarizationOnAudioData(base64Audio, sampleRate);
  }

  /**
   * Initialize known speakers for identification
   * @param speakers Array of known speakers with embeddings
   */
  async setKnownSpeakers(speakers: KnownSpeaker[]): Promise<number> {
    this.ensureInitialized();
    const result = await FluidAudioNative.initializeKnownSpeakers(speakers);
    return result.speakerCount;
  }

  /**
   * Check if diarization is available and ready
   */
  async isAvailable(): Promise<boolean> {
    return FluidAudioNative.isDiarizationAvailable();
  }

  /**
   * Get unique speakers from diarization result
   */
  getUniqueSpeakers(result: DiarizationResult): string[] {
    const speakers = new Set<string>();
    for (const segment of result.segments) {
      speakers.add(segment.speakerId);
    }
    return Array.from(speakers);
  }

  /**
   * Get speaking time per speaker
   */
  getSpeakingTime(result: DiarizationResult): Record<string, number> {
    const times: Record<string, number> = {};
    for (const segment of result.segments) {
      times[segment.speakerId] = (times[segment.speakerId] || 0) + segment.duration;
    }
    return times;
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error('Diarization not initialized. Call initialize() first.');
    }
  }
}

// ============================================================================
// TTS (Text-to-Speech)
// ============================================================================

/**
 * TTS Result with ArrayBuffer for New Architecture
 */
export interface TTSBufferResult {
  audioBuffer: ArrayBuffer;
  duration: number;
  sampleRate: number;
}

/**
 * TTS Manager for text-to-speech synthesis
 *
 * Supports both legacy bridge (base64) and JSI (zero-copy ArrayBuffer)
 * Note: TTS has a GPL dependency (ESpeakNG) - check license compatibility
 */
export class TTSManager {
  private initialized = false;

  /**
   * Initialize the TTS manager and download/compile models
   */
  async initialize(config?: TTSConfig): Promise<void> {
    await FluidAudioNative.initializeTts(config);
    this.initialized = true;
  }

  /**
   * Synthesize text to ArrayBuffer (zero-copy with JSI when available)
   * @param text Text to synthesize
   * @param voice Voice ID to use (optional, uses recommended voice if not specified)
   * @returns Audio buffer with metadata
   */
  async synthesizeBuffer(text: string, voice?: string): Promise<TTSBufferResult> {
    this.ensureInitialized();

    if (hasJSI()) {
      // Zero-copy path: returns ArrayBuffer directly
      return (global as any).FluidAudio_synthesize(text, voice ?? null);
    } else {
      // Legacy path: convert base64 to ArrayBuffer
      const result = await FluidAudioNative.synthesize(text, voice);
      return {
        audioBuffer: base64ToArrayBuffer(result.audioData),
        duration: result.duration,
        sampleRate: result.sampleRate,
      };
    }
  }

  /**
   * Synthesize text to speech (legacy base64 API)
   * @deprecated Use synthesizeBuffer() for better performance
   * @param text Text to synthesize
   * @param voice Voice ID to use (optional, uses recommended voice if not specified)
   * @returns Audio data as base64 with metadata
   */
  async synthesize(text: string, voice?: string): Promise<TTSResult> {
    this.ensureInitialized();
    return FluidAudioNative.synthesize(text, voice);
  }

  /**
   * Synthesize text and write directly to a file
   * @param text Text to synthesize
   * @param outputPath Absolute path for the output audio file
   * @param voice Voice ID to use (optional)
   */
  async synthesizeToFile(text: string, outputPath: string, voice?: string): Promise<void> {
    this.ensureInitialized();
    await FluidAudioNative.synthesizeToFile(text, voice ?? null, outputPath);
  }

  /**
   * Check if TTS is available and ready
   */
  async isAvailable(): Promise<boolean> {
    return FluidAudioNative.isTtsAvailable();
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error('TTS not initialized. Call initialize() first.');
    }
  }
}

// ============================================================================
// Cleanup
// ============================================================================

/**
 * Clean up all FluidAudio resources
 * Call this when unmounting components or when done using FluidAudio
 */
export async function cleanup(): Promise<void> {
  await FluidAudioNative.cleanup();
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Convert ArrayBuffer to base64 string (for legacy bridge fallback)
 */
function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Convert base64 string to ArrayBuffer
 */
function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

// ============================================================================
// Default Export
// ============================================================================

const FluidAudio = {
  // System
  getSystemInfo,
  isAppleSilicon,
  isNewArchitecture,
  hasZeroCopySupport,

  // Managers
  ASRManager,
  StreamingASRManager,
  VADManager,
  DiarizationManager,
  TTSManager,

  // Events
  onStreamingUpdate,
  onModelLoadProgress,
  onTranscriptionError,

  // Cleanup
  cleanup,
};

export default FluidAudio;
