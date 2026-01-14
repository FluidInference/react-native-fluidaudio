// Main FluidAudio API
export {
  default as FluidAudio,
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
  // Types
  type EventSubscription,
  type TTSBufferResult,
} from './FluidAudio';

// Re-export all types
export type {
  // System
  SystemInfo,
  // ASR
  ASRConfig,
  ASRResult,
  ASRInitResult,
  TokenTiming,
  ASRPerformanceMetrics,
  // Streaming ASR
  StreamingASRConfig,
  StreamingUpdate,
  StreamingStopResult,
  // VAD
  VADConfig,
  VADResult,
  VADChunkResult,
  // Diarization
  DiarizationConfig,
  DiarizationResult,
  DiarizationInitResult,
  SpeakerSegment,
  DiarizationTimings,
  KnownSpeaker,
  // TTS
  TTSConfig,
  TTSResult,
  TTSSynthesizeFileResult,
  // Events
  ModelLoadProgressEvent,
  TranscriptionErrorEvent,
} from './types';
