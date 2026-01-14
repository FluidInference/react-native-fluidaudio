# react-native-fluidaudio

React Native wrapper for [FluidAudio](../FluidAudio) - a Swift library for ASR, VAD, Speaker Diarization, and TTS on Apple platforms.

## Features

- **ASR (Automatic Speech Recognition)** - High-quality speech-to-text using Parakeet TDT models
- **Streaming ASR** - Real-time transcription from microphone or system audio
- **VAD (Voice Activity Detection)** - Detect speech segments in audio
- **Speaker Diarization** - Identify and track different speakers
- **TTS (Text-to-Speech)** - Natural voice synthesis using Kokoro TTS

## Requirements

- iOS 17.0+ / macOS 14.0+
- React Native 0.71+
- Apple Silicon (M1/M2/M3) - Intel Macs have limited support

## Installation

```bash
npm install react-native-fluidaudio
```

Add FluidAudio to your `ios/Podfile`:

```ruby
pod 'FluidAudio', :git => 'https://github.com/FluidInference/FluidAudio.git', :tag => 'v0.7.8'
```

Then install pods:

```bash
cd ios && pod install
```

**Note:** Requires **arm64** architecture (Apple Silicon). Simulator builds only work on M1/M2/M3 Macs.

## Usage

### Basic Transcription

```typescript
import { ASRManager, onModelLoadProgress } from 'react-native-fluidaudio';

// Monitor model loading progress
const subscription = onModelLoadProgress((event) => {
  console.log(`Model loading: ${event.status} (${event.progress}%)`);
});

// Initialize ASR (downloads models on first run)
const asr = new ASRManager();
await asr.initialize();

// Transcribe an audio file
const result = await asr.transcribeFile('/path/to/audio.wav');
console.log(result.text);
console.log(`Confidence: ${result.confidence}`);
console.log(`Processing speed: ${result.rtfx}x realtime`);

// Clean up
subscription.remove();
```

### Streaming Transcription

```typescript
import { StreamingASRManager, onStreamingUpdate } from 'react-native-fluidaudio';

const streaming = new StreamingASRManager();

// Start streaming with update callback
await streaming.start({ source: 'microphone' }, (update) => {
  console.log('Confirmed:', update.confirmed);
  console.log('Volatile:', update.volatile);
});

// Feed audio data (16-bit PCM, 16kHz, base64 encoded)
await streaming.feedAudio(base64AudioChunk);

// Stop and get final result
const result = await streaming.stop();
console.log('Final transcription:', result.text);
```

### Voice Activity Detection

```typescript
import { VADManager } from 'react-native-fluidaudio';

const vad = new VADManager();
await vad.initialize({ threshold: 0.85 });

// Process audio file
const result = await vad.processFile('/path/to/audio.wav');

// Get speech segments
const segments = vad.getSpeechSegments(result);
segments.forEach((seg) => {
  console.log(`Speech from ${seg.start}s to ${seg.end}s`);
});
```

### Speaker Diarization

```typescript
import { DiarizationManager } from 'react-native-fluidaudio';

const diarizer = new DiarizationManager();
await diarizer.initialize({
  clusteringThreshold: 0.7,
  numClusters: -1, // Auto-detect number of speakers
});

// Diarize audio file
const result = await diarizer.diarizeFile('/path/to/meeting.wav');

// Get speaker information
const speakers = diarizer.getUniqueSpeakers(result);
const speakingTime = diarizer.getSpeakingTime(result);

result.segments.forEach((segment) => {
  console.log(`${segment.speakerId}: ${segment.startTime}s - ${segment.endTime}s`);
});

// Pre-register known speakers for identification
await diarizer.setKnownSpeakers([
  { id: 'alice', name: 'Alice', embedding: aliceEmbedding },
  { id: 'bob', name: 'Bob', embedding: bobEmbedding },
]);
```

### Text-to-Speech

```typescript
import { TTSManager } from 'react-native-fluidaudio';

const tts = new TTSManager();
await tts.initialize({ variant: 'fiveSecond' });

// Synthesize to audio data
const result = await tts.synthesize('Hello, world!');
console.log(`Audio duration: ${result.duration}s`);
// result.audioData is base64-encoded 16-bit PCM

// Synthesize directly to file
await tts.synthesizeToFile('Hello, world!', '/path/to/output.wav');
```

### System Information

```typescript
import { getSystemInfo, isAppleSilicon } from 'react-native-fluidaudio';

const info = await getSystemInfo();
console.log(info.summary);
// e.g., "Apple M2 Pro, 16GB RAM, macOS 14.0"

if (await isAppleSilicon()) {
  // Full ML model support available
} else {
  // Intel Mac - some models may not work
}
```

### Cleanup

```typescript
import { cleanup } from 'react-native-fluidaudio';

// Clean up all resources when done
await cleanup();
```

## API Reference

### Managers

| Manager | Description |
|---------|-------------|
| `ASRManager` | Speech-to-text transcription |
| `StreamingASRManager` | Real-time streaming transcription |
| `VADManager` | Voice activity detection |
| `DiarizationManager` | Speaker identification |
| `TTSManager` | Text-to-speech synthesis |

### Events

| Event | Description |
|-------|-------------|
| `onStreamingUpdate` | Streaming transcription updates |
| `onModelLoadProgress` | Model download/compilation progress |
| `onTranscriptionError` | Transcription errors |

### Types

See [src/types.ts](./src/types.ts) for complete TypeScript definitions.


## Notes

### Model Loading

First initialization downloads and compiles ML models (~500MB total). This can take 20-30 seconds as Apple's Neural Engine compiles the models. Subsequent loads use cached compilations (~1 second).

### Intel Mac Support

Most ML models require Apple Silicon (ARM64). On Intel Macs:
- VAD works with CPU fallback
- ASR/Diarization may not work
- Use `isAppleSilicon()` to check before initializing

### TTS License

The TTS module uses ESpeakNG which is GPL licensed. Check license compatibility for your project.

## Architecture

This package uses the **Bridge-based Native Module** architecture for compatibility with React Native 0.71+.

Future versions may migrate to **Turbo Modules** (New Architecture) for improved performance. The async nature of audio processing means the Bridge overhead is minimal for this use case.

## License

MIT
