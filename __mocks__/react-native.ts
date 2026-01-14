// Mock React Native module for testing

export const NativeModules = {
  FluidAudioModule: {
    getSystemInfo: jest.fn().mockResolvedValue({
      isAppleSilicon: true,
      platform: 'ios',
      summary: 'Mock iOS Device',
    }),
    initializeAsr: jest.fn().mockResolvedValue({
      success: true,
      compilationDuration: 1.5,
    }),
    transcribeFile: jest.fn().mockResolvedValue({
      text: 'Hello world',
      confidence: 0.95,
      duration: 2.5,
      processingTime: 0.1,
      rtfx: 25.0,
    }),
    transcribeAudioData: jest.fn().mockResolvedValue({
      text: 'Test transcription',
      confidence: 0.92,
      duration: 1.0,
      processingTime: 0.05,
      rtfx: 20.0,
    }),
    isAsrAvailable: jest.fn().mockResolvedValue(true),
    startStreamingAsr: jest.fn().mockResolvedValue({ success: true }),
    feedStreamingAudio: jest.fn().mockResolvedValue({ success: true }),
    stopStreamingAsr: jest.fn().mockResolvedValue({
      text: 'Streaming result',
      success: true,
    }),
    initializeVad: jest.fn().mockResolvedValue({ success: true }),
    processVad: jest.fn().mockResolvedValue({
      results: [
        { chunkIndex: 0, probability: 0.95, isActive: true, processingTime: 0.01 },
        { chunkIndex: 1, probability: 0.1, isActive: false, processingTime: 0.01 },
      ],
      chunkSize: 4096,
      sampleRate: 16000,
    }),
    processVadAudioData: jest.fn().mockResolvedValue({
      results: [
        { chunkIndex: 0, probability: 0.9, isActive: true, processingTime: 0.01 },
      ],
      chunkSize: 4096,
      sampleRate: 16000,
    }),
    isVadAvailable: jest.fn().mockResolvedValue(true),
    initializeDiarization: jest.fn().mockResolvedValue({
      success: true,
      compilationDuration: 2.0,
    }),
    performDiarization: jest.fn().mockResolvedValue({
      segments: [
        {
          id: 'seg-1',
          speakerId: 'speaker_0',
          startTime: 0.0,
          endTime: 5.0,
          duration: 5.0,
          qualityScore: 0.9,
          embedding: new Array(256).fill(0.1),
        },
      ],
      speakerDatabase: {},
      timings: { total: 0.5, segmentation: 0.2, embedding: 0.2, clustering: 0.1 },
    }),
    performDiarizationOnAudioData: jest.fn().mockResolvedValue({
      segments: [],
      speakerDatabase: {},
    }),
    initializeKnownSpeakers: jest.fn().mockResolvedValue({
      success: true,
      speakerCount: 2,
    }),
    isDiarizationAvailable: jest.fn().mockResolvedValue(true),
    initializeTts: jest.fn().mockResolvedValue({ success: true }),
    synthesize: jest.fn().mockResolvedValue({
      audioData: 'base64encodedaudio',
      duration: 1.5,
      sampleRate: 24000,
    }),
    synthesizeToFile: jest.fn().mockResolvedValue({
      success: true,
      outputPath: '/path/to/output.wav',
    }),
    isTtsAvailable: jest.fn().mockResolvedValue(true),
    cleanup: jest.fn().mockResolvedValue({ success: true }),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
  },
};

export class NativeEventEmitter {
  private listeners: Map<string, Set<Function>> = new Map();

  constructor(_nativeModule: any) {}

  addListener(eventType: string, listener: Function) {
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, new Set());
    }
    this.listeners.get(eventType)!.add(listener);
    return {
      remove: () => {
        this.listeners.get(eventType)?.delete(listener);
      },
    };
  }

  removeAllListeners(eventType: string) {
    this.listeners.delete(eventType);
  }

  emit(eventType: string, ...args: any[]) {
    this.listeners.get(eventType)?.forEach((listener) => listener(...args));
  }
}

export const Platform = {
  OS: 'ios',
  select: <T extends Record<string, any>>(obj: T): T[keyof T] => obj.ios ?? obj.default,
};

export default {
  NativeModules,
  NativeEventEmitter,
  Platform,
};
