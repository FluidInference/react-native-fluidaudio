import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  // System Info
  getSystemInfo(): Promise<{
    isAppleSilicon: boolean;
    platform: string;
    summary: string;
  }>;

  // ASR
  initializeAsr(config: Object | null): Promise<{
    success: boolean;
    message: string;
  }>;

  transcribeFile(filePath: string): Promise<{
    text: string;
    duration: number;
    segments: Object[];
  }>;

  transcribeAudioData(base64Audio: string, sampleRate: number): Promise<{
    text: string;
    duration: number;
    segments: Object[];
  }>;

  isAsrAvailable(): Promise<boolean>;

  // Streaming ASR
  startStreamingAsr(config: Object | null): Promise<void>;
  feedStreamingAudio(base64Audio: string): Promise<void>;
  stopStreamingAsr(): Promise<{
    finalText: string;
    totalDuration: number;
  }>;

  // VAD
  initializeVad(config: Object | null): Promise<void>;
  processVad(filePath: string): Promise<{
    results: Object[];
    chunkSize: number;
    sampleRate: number;
  }>;
  processVadAudioData(base64Audio: string): Promise<{
    results: Object[];
    chunkSize: number;
    sampleRate: number;
  }>;
  isVadAvailable(): Promise<boolean>;

  // Diarization
  initializeDiarization(config: Object | null): Promise<{
    success: boolean;
    message: string;
  }>;
  performDiarization(filePath: string, sampleRate: number): Promise<{
    segments: Object[];
    speakerCount: number;
  }>;
  performDiarizationOnAudioData(base64Audio: string, sampleRate: number): Promise<{
    segments: Object[];
    speakerCount: number;
  }>;
  initializeKnownSpeakers(speakers: Object[]): Promise<{
    speakerCount: number;
  }>;
  isDiarizationAvailable(): Promise<boolean>;

  // TTS
  initializeTts(config: Object | null): Promise<void>;
  synthesize(text: string, voice: string | null): Promise<{
    audioData: string;
    duration: number;
    sampleRate: number;
  }>;
  synthesizeToFile(text: string, voice: string | null, outputPath: string): Promise<void>;
  isTtsAvailable(): Promise<boolean>;

  // Cleanup
  cleanup(): Promise<void>;

  // Events
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('FluidAudio');
