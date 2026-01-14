#!/bin/bash
# Setup script for creating a new React Native example app with FluidAudio

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLE_NAME="FluidAudioExample"

echo "=== FluidAudio Example App Setup ==="
echo ""

# Check for required tools
if ! command -v npx &> /dev/null; then
    echo "Error: npx is required. Please install Node.js."
    exit 1
fi

if ! command -v pod &> /dev/null; then
    echo "Warning: CocoaPods not found. You'll need it for iOS builds."
fi

# Create example app
echo "Creating React Native app..."
cd "$PACKAGE_DIR"

if [ -d "$EXAMPLE_NAME" ]; then
    echo "Example app already exists. Skipping creation."
else
    npx @react-native-community/cli init "$EXAMPLE_NAME" --skip-install
fi

cd "$EXAMPLE_NAME"

# Link local package
echo ""
echo "Linking react-native-fluidaudio..."
cat > package.json.tmp << EOF
{
  "name": "fluidaudioexample",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "android": "react-native run-android",
    "ios": "react-native run-ios",
    "start": "react-native start",
    "test": "jest",
    "lint": "eslint ."
  },
  "dependencies": {
    "react": "18.2.0",
    "react-native": "0.73.0",
    "react-native-fluidaudio": "file:.."
  },
  "devDependencies": {
    "@babel/core": "^7.24.0",
    "@babel/preset-env": "^7.24.0",
    "@babel/runtime": "^7.24.0",
    "@react-native/babel-preset": "^0.73.0",
    "@react-native/metro-config": "^0.73.0",
    "@types/react": "^18.2.0",
    "@types/react-native": "^0.73.0",
    "typescript": "^5.3.0"
  }
}
EOF
mv package.json.tmp package.json

# Install dependencies
echo ""
echo "Installing dependencies..."
npm install

# Copy example App.tsx
echo ""
echo "Copying example App.tsx..."
cp "$PACKAGE_DIR/example/App.tsx" ./App.tsx

# Setup iOS
if command -v pod &> /dev/null; then
    echo ""
    echo "Installing iOS pods..."
    cd ios
    pod install
    cd ..
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To run the example app:"
echo ""
echo "  iOS:"
echo "    cd $EXAMPLE_NAME && npx react-native run-ios"
echo ""
echo "  Start Metro:"
echo "    cd $EXAMPLE_NAME && npm start"
echo ""
echo "Note: First model initialization may take 20-30 seconds for compilation."
