import { NativeModules } from 'react-native';
import {
  ASRManager,
  StreamingASRManager,
  VADManager,
  DiarizationManager,
  TTSManager,
  getSystemInfo,
  isAppleSilicon,
  cleanup,
} from '../src';

const mockModule = NativeModules.FluidAudioModule;

describe('FluidAudio', () => {
  describe('System Info', () => {
    it('should get system info', async () => {
      const info = await getSystemInfo();

      expect(info.isAppleSilicon).toBe(true);
      expect(info.platform).toBe('ios');
      expect(mockModule.getSystemInfo).toHaveBeenCalledTimes(1);
    });

    it('should check Apple Silicon', async () => {
      const result = await isAppleSilicon();

      expect(result).toBe(true);
      expect(mockModule.getSystemInfo).toHaveBeenCalled();
    });
  });

  describe('ASRManager', () => {
    let asr: ASRManager;

    beforeEach(() => {
      asr = new ASRManager();
    });

    it('should initialize successfully', async () => {
      const result = await asr.initialize();

      expect(result.success).toBe(true);
      expect(result.compilationDuration).toBeGreaterThan(0);
      expect(mockModule.initializeAsr).toHaveBeenCalled();
    });

    it('should initialize with custom config', async () => {
      await asr.initialize({ sampleRate: 48000, streamingEnabled: false });

      expect(mockModule.initializeAsr).toHaveBeenCalledWith({
        sampleRate: 48000,
        streamingEnabled: false,
      });
    });

    it('should transcribe file after initialization', async () => {
      await asr.initialize();
      const result = await asr.transcribeFile('/path/to/audio.wav');

      expect(result.text).toBe('Hello world');
      expect(result.confidence).toBeGreaterThan(0);
      expect(result.rtfx).toBeGreaterThan(1);
      expect(mockModule.transcribeFile).toHaveBeenCalledWith('/path/to/audio.wav');
    });

    it('should throw error when transcribing without initialization', async () => {
      await expect(asr.transcribeFile('/path/to/audio.wav')).rejects.toThrow(
        'ASR not initialized'
      );
    });

    it('should transcribe audio data', async () => {
      await asr.initialize();
      const result = await asr.transcribe('base64audio', 16000);

      expect(result.text).toBe('Test transcription');
      expect(mockModule.transcribeAudioData).toHaveBeenCalledWith('base64audio', 16000);
    });

    it('should check availability', async () => {
      const available = await asr.isAvailable();

      expect(available).toBe(true);
    });
  });

  describe('StreamingASRManager', () => {
    let streaming: StreamingASRManager;

    beforeEach(() => {
      streaming = new StreamingASRManager();
    });

    it('should start streaming', async () => {
      await streaming.start();

      expect(streaming.isStreaming()).toBe(true);
      expect(mockModule.startStreamingAsr).toHaveBeenCalled();
    });

    it('should start streaming with config', async () => {
      await streaming.start({ source: 'microphone', chunkDuration: 0.5 });

      expect(mockModule.startStreamingAsr).toHaveBeenCalledWith({
        source: 'microphone',
        chunkDuration: 0.5,
      });
    });

    it('should throw when starting twice', async () => {
      await streaming.start();

      await expect(streaming.start()).rejects.toThrow('Streaming already in progress');
    });

    it('should feed audio while streaming', async () => {
      await streaming.start();
      await streaming.feedAudio('base64chunk');

      expect(mockModule.feedStreamingAudio).toHaveBeenCalledWith('base64chunk');
    });

    it('should throw when feeding audio without starting', async () => {
      await expect(streaming.feedAudio('base64chunk')).rejects.toThrow(
        'Streaming not started'
      );
    });

    it('should stop streaming and return result', async () => {
      await streaming.start();
      const result = await streaming.stop();

      expect(result.success).toBe(true);
      expect(result.text).toBe('Streaming result');
      expect(streaming.isStreaming()).toBe(false);
    });
  });

  describe('VADManager', () => {
    let vad: VADManager;

    beforeEach(() => {
      vad = new VADManager();
    });

    it('should initialize successfully', async () => {
      await vad.initialize();

      expect(mockModule.initializeVad).toHaveBeenCalled();
    });

    it('should initialize with custom threshold', async () => {
      await vad.initialize({ threshold: 0.9 });

      expect(mockModule.initializeVad).toHaveBeenCalledWith({ threshold: 0.9 });
    });

    it('should process file after initialization', async () => {
      await vad.initialize();
      const result = await vad.processFile('/path/to/audio.wav');

      expect(result.results.length).toBeGreaterThan(0);
      expect(result.chunkSize).toBe(4096);
      expect(result.sampleRate).toBe(16000);
    });

    it('should throw error when processing without initialization', async () => {
      await expect(vad.processFile('/path/to/audio.wav')).rejects.toThrow(
        'VAD not initialized'
      );
    });

    it('should extract speech segments', async () => {
      await vad.initialize();
      const result = await vad.processFile('/path/to/audio.wav');
      const segments = vad.getSpeechSegments(result);

      expect(segments.length).toBe(1);
      expect(segments[0]).toHaveProperty('start');
      expect(segments[0]).toHaveProperty('end');
    });

    it('should handle contiguous speech segments', () => {
      const mockResult = {
        results: [
          { chunkIndex: 0, probability: 0.9, isActive: true, processingTime: 0.01 },
          { chunkIndex: 1, probability: 0.85, isActive: true, processingTime: 0.01 },
          { chunkIndex: 2, probability: 0.1, isActive: false, processingTime: 0.01 },
        ],
        chunkSize: 4096,
        sampleRate: 16000,
      };

      const segments = vad.getSpeechSegments(mockResult);

      expect(segments.length).toBe(1);
      expect(segments[0]!.start).toBe(0);
    });
  });

  describe('DiarizationManager', () => {
    let diarizer: DiarizationManager;

    beforeEach(() => {
      diarizer = new DiarizationManager();
    });

    it('should initialize successfully', async () => {
      const result = await diarizer.initialize();

      expect(result.success).toBe(true);
      expect(mockModule.initializeDiarization).toHaveBeenCalled();
    });

    it('should initialize with custom config', async () => {
      await diarizer.initialize({
        clusteringThreshold: 0.8,
        numClusters: 2,
      });

      expect(mockModule.initializeDiarization).toHaveBeenCalledWith({
        clusteringThreshold: 0.8,
        numClusters: 2,
      });
    });

    it('should diarize file after initialization', async () => {
      await diarizer.initialize();
      const result = await diarizer.diarizeFile('/path/to/meeting.wav');

      expect(result.segments.length).toBeGreaterThan(0);
      expect(result.segments[0]).toHaveProperty('speakerId');
      expect(result.segments[0]).toHaveProperty('startTime');
      expect(result.segments[0]).toHaveProperty('endTime');
    });

    it('should throw error when diarizing without initialization', async () => {
      await expect(diarizer.diarizeFile('/path/to/audio.wav')).rejects.toThrow(
        'Diarization not initialized'
      );
    });

    it('should get unique speakers', async () => {
      await diarizer.initialize();
      const result = await diarizer.diarizeFile('/path/to/meeting.wav');
      const speakers = diarizer.getUniqueSpeakers(result);

      expect(speakers).toContain('speaker_0');
    });

    it('should calculate speaking time', async () => {
      await diarizer.initialize();
      const result = await diarizer.diarizeFile('/path/to/meeting.wav');
      const times = diarizer.getSpeakingTime(result);

      expect(times['speaker_0']).toBe(5.0);
    });

    it('should set known speakers', async () => {
      await diarizer.initialize();
      const count = await diarizer.setKnownSpeakers([
        { id: 'alice', name: 'Alice', embedding: new Array(256).fill(0.1) },
        { id: 'bob', name: 'Bob', embedding: new Array(256).fill(0.2) },
      ]);

      expect(count).toBe(2);
    });
  });

  describe('TTSManager', () => {
    let tts: TTSManager;

    beforeEach(() => {
      tts = new TTSManager();
    });

    it('should initialize successfully', async () => {
      await tts.initialize();

      expect(mockModule.initializeTts).toHaveBeenCalled();
    });

    it('should initialize with config', async () => {
      await tts.initialize({ variant: 'fiveSecond' });

      expect(mockModule.initializeTts).toHaveBeenCalledWith({ variant: 'fiveSecond' });
    });

    it('should synthesize text after initialization', async () => {
      await tts.initialize();
      const result = await tts.synthesize('Hello world');

      expect(result.audioData).toBeTruthy();
      expect(result.duration).toBeGreaterThan(0);
      expect(mockModule.synthesize).toHaveBeenCalledWith('Hello world', undefined);
    });

    it('should synthesize with custom voice', async () => {
      await tts.initialize();
      await tts.synthesize('Hello', 'custom_voice');

      expect(mockModule.synthesize).toHaveBeenCalledWith('Hello', 'custom_voice');
    });

    it('should throw error when synthesizing without initialization', async () => {
      await expect(tts.synthesize('Hello')).rejects.toThrow('TTS not initialized');
    });

    it('should synthesize to file', async () => {
      await tts.initialize();
      await tts.synthesizeToFile('Hello', '/path/to/output.wav');

      expect(mockModule.synthesizeToFile).toHaveBeenCalledWith(
        'Hello',
        null,
        '/path/to/output.wav'
      );
    });
  });

  describe('Cleanup', () => {
    it('should cleanup all resources', async () => {
      await cleanup();

      expect(mockModule.cleanup).toHaveBeenCalledTimes(1);
    });
  });
});
