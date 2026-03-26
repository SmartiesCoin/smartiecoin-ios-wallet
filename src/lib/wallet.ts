import * as bip39 from 'bip39';
import BIP32Factory, { type BIP32API } from 'bip32';
import * as ecc from '@bitcoinerlab/secp256k1';
import { payments } from 'bitcoinjs-lib';
import { Buffer } from 'buffer';
import CryptoJS from 'crypto-js';
import * as SecureStore from 'expo-secure-store';
import { smartiecoin, DERIVATION_PATH } from './network';

const bip32: BIP32API = BIP32Factory(ecc);

const STORE_KEY = 'smt_wallet';

export interface WalletData {
  address: string;
  encryptedMnemonic: string;
  encryptedPrivKey: string;
}

// Generate a new 12-word mnemonic
export function generateMnemonic(): string {
  return bip39.generateMnemonic(128);
}

// Derive address and private key from mnemonic
export function deriveFromMnemonic(mnemonic: string): {
  address: string;
  privateKey: Uint8Array;
  publicKey: Uint8Array;
} {
  const seed = bip39.mnemonicToSeedSync(mnemonic);
  const root = bip32.fromSeed(Buffer.from(seed), smartiecoin);
  const child = root.derivePath(DERIVATION_PATH);

  if (!child.privateKey) {
    throw new Error('Failed to derive private key');
  }

  const { address } = payments.p2pkh({
    pubkey: Buffer.from(child.publicKey),
    network: smartiecoin,
  });

  if (!address) {
    throw new Error('Failed to derive address');
  }

  return {
    address,
    privateKey: child.privateKey,
    publicKey: child.publicKey,
  };
}

// Validate a mnemonic phrase
export function validateMnemonic(mnemonic: string): boolean {
  return bip39.validateMnemonic(mnemonic.trim().toLowerCase());
}

// Encrypt with AES (password-based, CryptoJS uses PBKDF2 internally)
export function encrypt(plaintext: string, password: string): string {
  return CryptoJS.AES.encrypt(plaintext, password).toString();
}

// Decrypt with AES
export function decrypt(ciphertext: string, password: string): string {
  const bytes = CryptoJS.AES.decrypt(ciphertext, password);
  const result = bytes.toString(CryptoJS.enc.Utf8);
  if (!result) throw new Error('Wrong password');
  return result;
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
    Buffer.from(privateKey).toString('hex'),
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
    Buffer.from(privateKey).toString('hex'),
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
    privateKey: Uint8Array.from(Buffer.from(privKeyHex, 'hex')),
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
