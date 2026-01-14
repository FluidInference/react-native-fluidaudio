import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

// Codegen types for native module interface
export interface Spec extends TurboModule {
  // System Info
  getSystemInfo(): Promise<{
    isAppleSilicon: boolean;
    isIntelMac: boolean;
    platform: string;
    summary: string;
  }>;

  // ASR (Automatic Speech Recognition)
  initializeAsr(config: {
    sampleRate?: number;
    streamingEnabled?: boolean;
  } | null): Promise<{
    success: boolean;
    compilationDuration: number;
  }>;

  transcribeFile(filePath: string): Promise<{
    text: string;
    confidence: number;
    duration: number;
    processingTime: number;
    rtfx: number;
    tokenTimings?: Array<{
      token: string;
      tokenId: number;
      startTime: number;
      endTime: number;
      confidence: number;
    }>;
    performanceMetrics?: {
      preprocessDuration: number;
      encoderDuration: number;
      decoderDuration: number;
    };
  }>;

  // JSI: Zero-copy audio buffer transcription
  transcribeAudioBuffer(
    audioBuffer: ArrayBuffer,
    sampleRate: number
  ): Promise<{
    text: string;
    confidence: number;
    duration: number;
    processingTime: number;
    rtfx: number;
  }>;

  isAsrAvailable(): Promise<boolean>;

  // Streaming ASR
  startStreamingAsr(config: {
    source?: string;
    chunkDuration?: number;
  } | null): Promise<{ success: boolean }>;

  // JSI: Zero-copy streaming audio feed
  feedStreamingAudioBuffer(audioBuffer: ArrayBuffer): Promise<{ success: boolean }>;

  stopStreamingAsr(): Promise<{
    text: string;
    success: boolean;
  }>;

  // VAD (Voice Activity Detection)
  initializeVad(config: {
    threshold?: number;
    debugMode?: boolean;
  } | null): Promise<{ success: boolean }>;

  processVadFile(filePath: string): Promise<{
    results: Array<{
      chunkIndex: number;
      probability: number;
      isActive: boolean;
      processingTime: number;
    }>;
    chunkSize: number;
    sampleRate: number;
  }>;

  // JSI: Zero-copy VAD processing
  processVadBuffer(audioBuffer: ArrayBuffer): Promise<{
    results: Array<{
      chunkIndex: number;
      probability: number;
      isActive: boolean;
      processingTime: number;
    }>;
    chunkSize: number;
    sampleRate: number;
  }>;

  isVadAvailable(): Promise<boolean>;

  // Diarization
  initializeDiarization(config: {
    clusteringThreshold?: number;
    minSpeechDuration?: number;
    minSilenceGap?: number;
    numClusters?: number;
    debugMode?: boolean;
  } | null): Promise<{
    success: boolean;
    compilationDuration: number;
  }>;

  performDiarizationFile(
    filePath: string,
    sampleRate: number
  ): Promise<{
    segments: Array<{
      id: string;
      speakerId: string;
      startTime: number;
      endTime: number;
      duration: number;
      qualityScore: number;
      embedding: number[];
    }>;
    speakerDatabase?: Object;
    timings?: {
      total: number;
      segmentation: number;
      embedding: number;
      clustering: number;
    };
  }>;

  // JSI: Zero-copy diarization
  performDiarizationBuffer(
    audioBuffer: ArrayBuffer,
    sampleRate: number
  ): Promise<{
    segments: Array<{
      id: string;
      speakerId: string;
      startTime: number;
      endTime: number;
      duration: number;
      qualityScore: number;
      embedding: number[];
    }>;
  }>;

  initializeKnownSpeakers(
    speakers: Array<{
      id: string;
      name: string;
      embedding: number[];
    }>
  ): Promise<{ success: boolean; speakerCount: number }>;

  isDiarizationAvailable(): Promise<boolean>;

  // TTS (Text-to-Speech)
  initializeTts(config: {
    variant?: string;
    debugMode?: boolean;
  } | null): Promise<{ success: boolean }>;

  // JSI: Returns ArrayBuffer instead of base64
  synthesize(
    text: string,
    voice: string | null
  ): Promise<{
    audioBuffer: ArrayBuffer;
    duration: number;
    sampleRate: number;
  }>;

  synthesizeToFile(
    text: string,
    voice: string | null,
    outputPath: string
  ): Promise<{
    success: boolean;
    outputPath: string;
  }>;

  isTtsAvailable(): Promise<boolean>;

  // Cleanup
  cleanup(): Promise<{ success: boolean }>;

  // Event emitter support
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('FluidAudio');
