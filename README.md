# react-native-fluidaudio

[![DeepWiki](https://img.shields.io/badge/DeepWiki-FluidInference%2Freact--native--fluidaudio-blue?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiNmZmZmZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNNCAxOWgxNmMuNTUgMCAxLS40NSAxLTFWNmMwLS41NS0uNDUtMS0xLTFINEMzLjQ1IDUgMyA1LjQ1IDMgNnYxMmMwIC41NS40NSAxIDEgMXoiLz48cGF0aCBkPSJNMTIgOHY4Ii8+PHBhdGggZD0iTTggMTJoOCIvPjwvc3ZnPg==)](https://deepwiki.com/FluidInference/react-native-fluidaudio)

React Native wrapper for [FluidAudio](https://github.com/FluidInference/FluidAudio) - a Swift library for ASR, VAD, Speaker Diarization, and TTS on Apple platforms.

<p align="center">
  <img width="750" height="1626" alt="image" src="https://github.com/user-attachments/assets/3b6d94fc-e71f-4178-881d-3b37f89c83c7" />

</p>

## Features

- **ASR (Automatic Speech Recognition)** - High-quality speech-to-text using Parakeet TDT models
- **Streaming ASR** - Real-time transcription from microphone or system audio
- **VAD (Voice Activity Detection)** - Detect speech segments in audio
- **Speaker Diarization** - Identify and track different speakers
- **TTS (Text-to-Speech)** - Natural voice synthesis using Kokoro TTS

## Requirements

- iOS 17.0+
- React Native 0.71+ or Expo SDK 50+

## Installation

### React Native CLI

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

### Expo

For Expo projects, use a [development build](https://docs.expo.dev/develop/development-builds/introduction/):

```bash
npx expo install react-native-fluidaudio
npx expo prebuild
npx expo run:ios
```

> **Note:** Expo Go is not supported - native modules require a development build.

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
import { getSystemInfo } from 'react-native-fluidaudio';

const info = await getSystemInfo();
console.log(info.summary);
// e.g., "Apple A17 Pro, iOS 17.0"
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

### TTS License

The TTS module uses ESpeakNG which is GPL licensed. Check license compatibility for your project.

## License

MIT
