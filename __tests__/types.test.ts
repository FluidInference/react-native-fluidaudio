import type {
  SystemInfo,
  ASRConfig,
  ASRResult,
  ASRInitResult,
  StreamingASRConfig,
  StreamingUpdate,
  VADConfig,
  VADResult,
  VADChunkResult,
  DiarizationConfig,
  DiarizationResult,
  SpeakerSegment,
  KnownSpeaker,
  TTSConfig,
  TTSResult,
  ModelLoadProgressEvent,
} from '../src';

describe('Type Definitions', () => {
  describe('SystemInfo', () => {
    it('should have correct shape', () => {
      const info: SystemInfo = {
        isAppleSilicon: true,
        isIntelMac: false,
        platform: 'ios',
        summary: 'Test device',
      };

      expect(info.isAppleSilicon).toBe(true);
      expect(info.platform).toBe('ios');
    });
  });

  describe('ASR Types', () => {
    it('should define ASRConfig correctly', () => {
      const config: ASRConfig = {
        sampleRate: 16000,
        streamingEnabled: true,
        streamingThreshold: 480000,
      };

      expect(config.sampleRate).toBe(16000);
    });

    it('should allow partial ASRConfig', () => {
      const config: ASRConfig = {};
      expect(config).toBeDefined();
    });

    it('should define ASRResult correctly', () => {
      const result: ASRResult = {
        text: 'Hello',
        confidence: 0.95,
        duration: 2.0,
        processingTime: 0.1,
        rtfx: 20.0,
      };

      expect(result.rtfx).toBe(20.0);
    });

    it('should define ASRResult with optional fields', () => {
      const result: ASRResult = {
        text: 'Hello',
        confidence: 0.95,
        duration: 2.0,
        processingTime: 0.1,
        rtfx: 20.0,
        tokenTimings: [
          {
            token: 'Hello',
            tokenId: 1,
            startTime: 0,
            endTime: 0.5,
            confidence: 0.9,
          },
        ],
        performanceMetrics: {
          preprocessDuration: 0.01,
          encoderDuration: 0.05,
          decoderDuration: 0.04,
        },
      };

      expect(result.tokenTimings).toHaveLength(1);
    });
  });

  describe('Streaming Types', () => {
    it('should define StreamingASRConfig correctly', () => {
      const config: StreamingASRConfig = {
        source: 'microphone',
        chunkDuration: 0.5,
      };

      expect(config.source).toBe('microphone');
    });

    it('should support system audio source', () => {
      const config: StreamingASRConfig = {
        source: 'system',
      };

      expect(config.source).toBe('system');
    });

    it('should define StreamingUpdate correctly', () => {
      const update: StreamingUpdate = {
        volatile: 'partial',
        confirmed: 'full',
        isFinal: false,
      };

      expect(update.isFinal).toBe(false);
    });
  });

  describe('VAD Types', () => {
    it('should define VADConfig correctly', () => {
      const config: VADConfig = {
        threshold: 0.85,
        debugMode: false,
      };

      expect(config.threshold).toBe(0.85);
    });

    it('should define VADChunkResult correctly', () => {
      const chunk: VADChunkResult = {
        chunkIndex: 0,
        probability: 0.95,
        isActive: true,
        processingTime: 0.01,
      };

      expect(chunk.isActive).toBe(true);
    });

    it('should define VADResult correctly', () => {
      const result: VADResult = {
        results: [
          { chunkIndex: 0, probability: 0.9, isActive: true, processingTime: 0.01 },
        ],
        chunkSize: 4096,
        sampleRate: 16000,
      };

      expect(result.chunkSize).toBe(4096);
    });
  });

  describe('Diarization Types', () => {
    it('should define DiarizationConfig correctly', () => {
      const config: DiarizationConfig = {
        clusteringThreshold: 0.7,
        minSpeechDuration: 1.0,
        minSilenceGap: 0.5,
        numClusters: -1,
        debugMode: false,
      };

      expect(config.clusteringThreshold).toBe(0.7);
    });

    it('should define SpeakerSegment correctly', () => {
      const segment: SpeakerSegment = {
        id: 'seg-1',
        speakerId: 'speaker_0',
        startTime: 0.0,
        endTime: 5.0,
        duration: 5.0,
        qualityScore: 0.9,
        embedding: new Array(256).fill(0.1),
      };

      expect(segment.embedding.length).toBe(256);
    });

    it('should define KnownSpeaker correctly', () => {
      const speaker: KnownSpeaker = {
        id: 'alice',
        name: 'Alice',
        embedding: new Array(256).fill(0.1),
      };

      expect(speaker.name).toBe('Alice');
    });
  });

  describe('TTS Types', () => {
    it('should define TTSConfig correctly', () => {
      const config: TTSConfig = {
        debugMode: false,
        variant: 'fiveSecond',
      };

      expect(config.variant).toBe('fiveSecond');
    });

    it('should support fifteenSecond variant', () => {
      const config: TTSConfig = {
        variant: 'fifteenSecond',
      };

      expect(config.variant).toBe('fifteenSecond');
    });

    it('should define TTSResult correctly', () => {
      const result: TTSResult = {
        audioData: 'base64data',
        duration: 1.5,
        sampleRate: 24000,
      };

      expect(result.sampleRate).toBe(24000);
    });
  });

  describe('Event Types', () => {
    it('should define ModelLoadProgressEvent correctly', () => {
      const event: ModelLoadProgressEvent = {
        type: 'asr',
        status: 'downloading',
        progress: 50,
      };

      expect(event.status).toBe('downloading');
    });

    it('should allow all status values', () => {
      const statuses: ModelLoadProgressEvent['status'][] = [
        'downloading',
        'compiling',
        'ready',
      ];

      statuses.forEach((status) => {
        const event: ModelLoadProgressEvent = { status, progress: 100 };
        expect(event.status).toBe(status);
      });
    });
  });
});
