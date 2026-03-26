// Must be imported BEFORE any crypto library
import 'react-native-get-random-values';
import { Buffer } from 'buffer';

// Polyfill Buffer globally for bitcoinjs-lib and friends
(globalThis as any).Buffer = Buffer;
