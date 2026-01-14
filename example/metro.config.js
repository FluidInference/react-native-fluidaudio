const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const path = require('path');

const root = path.resolve(__dirname, '..');

const config = {
  watchFolders: [root],
  resolver: {
    extraNodeModules: {
      'react-native-fluidaudio': root,
    },
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
