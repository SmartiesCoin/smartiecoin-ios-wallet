import { networks } from 'bitcoinjs-lib';

// Smartiecoin network parameters
// P2PKH: 0x3F (63) = addresses start with 'S'
// P2SH:  0x52 (82) = addresses start with 'R'
// WIF:   0x80 (128) = standard
// BIP44 coin_type: 5001
export const smartiecoin: networks.Network = {
  messagePrefix: '\x19Smartiecoin Signed Message:\n',
  bech32: 'smt',
  bip32: {
    public: 0x0488b21e,
    private: 0x0488ade4,
  },
  pubKeyHash: 0x3f,
  scriptHash: 0x52,
  wif: 0x80,
};

export const BIP44_COIN_TYPE = 5001;
export const DERIVATION_PATH = `m/44'/${BIP44_COIN_TYPE}'/0'/0/0`;

// 1 SMT = 100,000,000 duffs
export const COIN = 100_000_000;

export const MIN_FEE_RATE = 1;
export const DEFAULT_FEE_RATE = 10;

// API base URL - points to the web wallet backend
// Change this to your deployed backend URL
export const API_BASE = 'https://wallet.smartiecoin.com/api';
