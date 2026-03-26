const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// Polyfill Node.js core modules for React Native
config.resolver.extraNodeModules = {
  stream: require.resolve('readable-stream'),
};

module.exports = config;
