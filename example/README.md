# FluidAudio Example

Example React Native app demonstrating the `react-native-fluidaudio` package.

## Requirements

- macOS with Xcode 15+
- Node.js 18+
- CocoaPods

## Setup

```bash
# Install dependencies
npm install

# Install CocoaPods
cd ios && pod install && cd ..
```

## Running

```bash
# Start Metro bundler
npm start

# Run on iOS Simulator (in another terminal)
npm run ios
```

## Features Demonstrated

- **System Info**: Shows device capabilities
- **ASR**: Speech-to-text initialization
- **VAD**: Voice activity detection
- **Diarization**: Speaker identification
- **TTS**: Text-to-speech synthesis

## Notes

- First run downloads ~500MB of ML models
- Model compilation takes 20-30 seconds on first launch
