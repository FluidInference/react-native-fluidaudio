# FluidAudio Example

Example React Native app demonstrating the `react-native-fluidaudio` package.

## Requirements

- macOS with Apple Silicon (M1/M2/M3/M4)
- Xcode 15+
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

## New Architecture

To enable TurboModules and JSI zero-copy:

```bash
# Clean and reinstall pods with New Architecture
cd ios
RCT_NEW_ARCH_ENABLED=1 pod install
cd ..

# Run the app
npm run ios
```

## Features Demonstrated

- **System Info**: Shows device capabilities and architecture detection
- **ASR**: Speech-to-text initialization
- **VAD**: Voice activity detection
- **Diarization**: Speaker identification
- **TTS**: Text-to-speech synthesis

## Notes

- First run downloads ~500MB of ML models
- Model compilation takes 20-30 seconds on first launch
- Requires Apple Silicon for full ML model support
