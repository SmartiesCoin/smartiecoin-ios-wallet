// Run with: node assets/generate-icons.js
// Generates placeholder PNG icons for the app
// Replace these with proper branded icons before release

const fs = require('fs');

// Simple 1x1 purple PNG (placeholder)
// In production, replace icon.png (1024x1024) and splash.png (1284x2778) with proper assets
const placeholderPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/HwADBwIAMCbHYQAAAABJRU5ErkJggg==',
  'base64'
);

fs.writeFileSync(__dirname + '/icon.png', placeholderPng);
fs.writeFileSync(__dirname + '/splash.png', placeholderPng);
fs.writeFileSync(__dirname + '/adaptive-icon.png', placeholderPng);

console.log('Placeholder icons generated. Replace with proper 1024x1024 icon.png before release.');
