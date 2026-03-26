import { generateMnemonic as genMnemonic, mnemonicToSeedSync, validateMnemonic as valMnemonic } from '@scure/bip39';
import { wordlist } from '@scure/bip39/wordlists/english';
import { HDKey } from '@scure/bip32';
import * as ecc from '@bitcoinerlab/secp256k1';
import { payments } from 'bitcoinjs-lib';
import { Buffer } from 'buffer';
import { pbkdf2 } from '@noble/hashes/pbkdf2';
import { sha256 } from '@noble/hashes/sha2';
import { gcm } from '@noble/ciphers/aes';
import { randomBytes } from '@noble/ciphers/utils';
import { bytesToHex, hexToBytes } from '@noble/hashes/utils';
import * as SecureStore from 'expo-secure-store';
import { smartiecoin, DERIVATION_PATH } from './network';

// Initialize bitcoinjs-lib with secp256k1
import { initEccLib } from 'bitcoinjs-lib';
initEccLib(ecc);

const STORE_KEY = 'smt_wallet';

export interface WalletData {
  address: string;
  encryptedMnemonic: string;
  encryptedPrivKey: string;
}

// Generate a new 12-word mnemonic
export function generateMnemonic(): string {
  return genMnemonic(wordlist, 128);
}

// Derive address and private key from mnemonic
export function deriveFromMnemonic(mnemonic: string): {
  address: string;
  privateKey: Uint8Array;
  publicKey: Uint8Array;
} {
  const seed = mnemonicToSeedSync(mnemonic);
  const root = HDKey.fromMasterSeed(seed, {
    public: smartiecoin.bip32.public,
    private: smartiecoin.bip32.private,
  });
  const child = root.derive(DERIVATION_PATH);

  if (!child.privateKey) {
    throw new Error('Failed to derive private key');
  }

  const { address } = payments.p2pkh({
    pubkey: Buffer.from(child.publicKey!),
    network: smartiecoin,
  });

  if (!address) {
    throw new Error('Failed to derive address');
  }

  return {
    address,
    privateKey: child.privateKey,
    publicKey: child.publicKey!,
  };
}

// Validate a mnemonic phrase
export function validateMnemonic(mnemonic: string): boolean {
  return valMnemonic(mnemonic.trim().toLowerCase(), wordlist);
}

// Encrypt with AES-256-GCM + PBKDF2 (pure JS, no Node.js deps)
export function encrypt(plaintext: string, password: string): string {
  const salt = randomBytes(16);
  const nonce = randomBytes(12);
  const key = pbkdf2(sha256, new TextEncoder().encode(password), salt, {
    c: 100_000,
    dkLen: 32,
  });
  const aes = gcm(key, nonce);
  const ciphertext = aes.encrypt(new TextEncoder().encode(plaintext));

  // Combine: salt(16) + nonce(12) + ciphertext
  const combined = new Uint8Array(salt.length + nonce.length + ciphertext.length);
  combined.set(salt, 0);
  combined.set(nonce, salt.length);
  combined.set(ciphertext, salt.length + nonce.length);

  return bytesToHex(combined);
}

// Decrypt with AES-256-GCM + PBKDF2
export function decrypt(encryptedHex: string, password: string): string {
  const combined = hexToBytes(encryptedHex);
  const salt = combined.slice(0, 16);
  const nonce = combined.slice(16, 28);
  const ciphertext = combined.slice(28);

  const key = pbkdf2(sha256, new TextEncoder().encode(password), salt, {
    c: 100_000,
    dkLen: 32,
  });
  const aes = gcm(key, nonce);

  try {
    const decrypted = aes.decrypt(ciphertext);
    return new TextDecoder().decode(decrypted);
  } catch {
    throw new Error('Wrong password');
  }
}

// Create and encrypt a new wallet
export function createWallet(password: string): {
  walletData: WalletData;
  mnemonic: string;
} {
  const mnemonic = generateMnemonic();
  const { address, privateKey } = deriveFromMnemonic(mnemonic);

  const encryptedMnemonic = encrypt(mnemonic, password);
  const encryptedPrivKey = encrypt(
    bytesToHex(privateKey),
    password
  );

  return {
    walletData: { address, encryptedMnemonic, encryptedPrivKey },
    mnemonic,
  };
}

// Import wallet from mnemonic
export function importWallet(mnemonic: string, password: string): WalletData {
  if (!validateMnemonic(mnemonic)) {
    throw new Error('Invalid mnemonic phrase');
  }

  const cleaned = mnemonic.trim().toLowerCase();
  const { address, privateKey } = deriveFromMnemonic(cleaned);

  const encryptedMnemonic = encrypt(cleaned, password);
  const encryptedPrivKey = encrypt(
    bytesToHex(privateKey),
    password
  );

  return { address, encryptedMnemonic, encryptedPrivKey };
}

// Unlock wallet (decrypt private key)
export function unlockWallet(
  walletData: WalletData,
  password: string
): { privateKey: Uint8Array; mnemonic: string } {
  const mnemonic = decrypt(walletData.encryptedMnemonic, password);
  const privKeyHex = decrypt(walletData.encryptedPrivKey, password);

  return {
    privateKey: hexToBytes(privKeyHex),
    mnemonic,
  };
}

// Save wallet to iOS Keychain via SecureStore
export async function saveWallet(walletData: WalletData): Promise<void> {
  await SecureStore.setItemAsync(STORE_KEY, JSON.stringify(walletData));
}

// Load wallet from SecureStore
export async function loadWallet(): Promise<WalletData | null> {
  const raw = await SecureStore.getItemAsync(STORE_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as WalletData;
  } catch {
    return null;
  }
}

// Delete wallet from SecureStore
export async function deleteWallet(): Promise<void> {
  await SecureStore.deleteItemAsync(STORE_KEY);
}
