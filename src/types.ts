/**
 * FluidAudio React Native Types
 */

// ============================================================================
// System Info
// ============================================================================

export interface SystemInfo {
  isAppleSilicon: boolean;
  isIntelMac: boolean;
  platform: 'ios' | 'macos' | 'unknown';
  summary: string;
}

// ============================================================================
// ASR (Automatic Speech Recognition)
// ============================================================================

export interface ASRConfig {
  /** Sample rate in Hz (default: 16000) */
  sampleRate?: number;
  /** Enable streaming for long audio (default: true) */
  streamingEnabled?: boolean;
  /** Streaming threshold in samples (default: 480000 ~30s) */
  streamingThreshold?: number;
}

export interface TokenTiming {
  token: string;
  tokenId: number;
  startTime: number;
  endTime: number;
  confidence: number;
}

export interface ASRPerformanceMetrics {
  preprocessDuration: number;
  encoderDuration: number;
  decoderDuration: number;
}

export interface ASRResult {
  /** Transcribed text */
  text: string;
  /** Overall confidence score (0-1) */
  confidence: number;
  /** Audio duration in seconds */
  duration: number;
  /** Processing time in seconds */
  processingTime: number;
  /** Real-time factor (duration / processingTime) */
  rtfx: number;
  /** Per-token timing information */
  tokenTimings?: TokenTiming[];
  /** Detailed performance metrics */
  performanceMetrics?: ASRPerformanceMetrics;
}

export interface ASRInitResult {
  success: boolean;
  compilationDuration: number;
}

// ============================================================================
// Streaming ASR
// ============================================================================

export interface StreamingASRConfig {
  /** Audio source: 'microphone' or 'system' (macOS only) */
  source?: 'microphone' | 'system';
  /** Chunk duration in seconds */
  chunkDuration?: number;
}

export interface StreamingUpdate {
  /** Current volatile (unconfirmed) transcript */
  volatile: string;
  /** Confirmed transcript */
  confirmed: string;
  /** Whether this is the final update */
  isFinal: boolean;
}

export interface StreamingStopResult {
  text: string;
  success: boolean;
}

// ============================================================================
// VAD (Voice Activity Detection)
// ============================================================================

export interface VADConfig {
  /** Voice activity threshold (0-1, default: 0.85) */
  threshold?: number;
  /** Enable debug mode */
  debugMode?: boolean;
}

export interface VADChunkResult {
  /** Chunk index in the audio */
  chunkIndex: number;
  /** Voice activity probability (0-1) */
  probability: number;
  /** Whether voice activity is detected */
  isActive: boolean;
  /** Processing time for this chunk */
  processingTime: number;
}

export interface VADResult {
  /** Per-chunk VAD results */
  results: VADChunkResult[];
  /** Chunk size in samples */
  chunkSize: number;
  /** Sample rate used */
  sampleRate: number;
}

// ============================================================================
// Diarization (Speaker Identification)
// ============================================================================

export interface DiarizationConfig {
  /** Clustering threshold (0.5-0.9, default: 0.7) */
  clusteringThreshold?: number;
  /** Minimum speech duration in seconds (default: 1.0) */
  minSpeechDuration?: number;
  /** Minimum silence gap in seconds (default: 0.5) */
  minSilenceGap?: number;
  /** Number of speakers (-1 for automatic, default: -1) */
  numClusters?: number;
  /** Enable debug mode */
  debugMode?: boolean;
}

export interface SpeakerSegment {
  /** Unique segment ID */
  id: string;
  /** Speaker identifier */
  speakerId: string;
  /** Start time in seconds */
  startTime: number;
  /** End time in seconds */
  endTime: number;
  /** Segment duration in seconds */
  duration: number;
  /** Quality score for this segment */
  qualityScore: number;
  /** 256-dimensional speaker embedding */
  embedding: number[];
}

export interface DiarizationTimings {
  total: number;
  segmentation: number;
  embedding: number;
  clustering: number;
}

export interface DiarizationResult {
  /** Speaker segments with timing and identity */
  segments: SpeakerSegment[];
  /** Speaker embeddings database */
  speakerDatabase?: Record<string, number[]>;
  /** Processing timings */
  timings?: DiarizationTimings;
}

export interface DiarizationInitResult {
  success: boolean;
  compilationDuration: number;
}

export interface KnownSpeaker {
  /** Unique speaker ID */
  id: string;
  /** Speaker display name */
  name: string;
  /** 256-dimensional speaker embedding */
  embedding: number[];
}

// ============================================================================
// TTS (Text-to-Speech)
// ============================================================================

export interface TTSConfig {
  /** Enable debug mode */
  debugMode?: boolean;
  /** Model variant: 'fiveSecond' or 'fifteenSecond' */
  variant?: 'fiveSecond' | 'fifteenSecond';
}

export interface TTSResult {
  /** Base64-encoded audio data */
  audioData: string;
  /** Audio duration in seconds */
  duration: number;
  /** Sample rate */
  sampleRate: number;
}

// ============================================================================
// Events
// ============================================================================

export interface ModelLoadProgressEvent {
  type?: 'asr' | 'diarization' | 'vad' | 'tts';
  status: 'downloading' | 'compiling' | 'ready';
  progress: number;
}

export interface TranscriptionErrorEvent {
  code: string;
  message: string;
}

export interface TTSSynthesizeFileResult {
  success: boolean;
  outputPath: string;
}

// ============================================================================
// Native Module Interface
// ============================================================================

export interface FluidAudioNativeModule {
  // System
  getSystemInfo(): Promise<SystemInfo>;

  // ASR
  initializeAsr(config?: ASRConfig): Promise<ASRInitResult>;
  transcribeFile(filePath: string): Promise<ASRResult>;
  transcribeAudioData(base64Audio: string, sampleRate: number): Promise<ASRResult>;
  isAsrAvailable(): Promise<boolean>;

  // Streaming ASR
  startStreamingAsr(config?: StreamingASRConfig): Promise<{ success: boolean }>;
  feedStreamingAudio(base64Audio: string): Promise<{ success: boolean }>;
  stopStreamingAsr(): Promise<StreamingStopResult>;

  // VAD
  initializeVad(config?: VADConfig): Promise<{ success: boolean }>;
  processVad(filePath: string): Promise<VADResult>;
  processVadAudioData(base64Audio: string): Promise<VADResult>;
  isVadAvailable(): Promise<boolean>;

  // Diarization
  initializeDiarization(config?: DiarizationConfig): Promise<DiarizationInitResult>;
  performDiarization(filePath: string, sampleRate: number): Promise<DiarizationResult>;
  performDiarizationOnAudioData(
    base64Audio: string,
    sampleRate: number
  ): Promise<DiarizationResult>;
  initializeKnownSpeakers(
    speakers: KnownSpeaker[]
  ): Promise<{ success: boolean; speakerCount: number }>;
  isDiarizationAvailable(): Promise<boolean>;

  // TTS
  initializeTts(config?: TTSConfig): Promise<{ success: boolean }>;
  synthesize(text: string, voice?: string): Promise<TTSResult>;
  synthesizeToFile(text: string, voice: string | null, outputPath: string): Promise<TTSSynthesizeFileResult>;
  isTtsAvailable(): Promise<boolean>;

  // Cleanup
  cleanup(): Promise<{ success: boolean }>;

  // Event emitter methods
  addListener(eventType: string): void;
  removeListeners(count: number): void;
}
