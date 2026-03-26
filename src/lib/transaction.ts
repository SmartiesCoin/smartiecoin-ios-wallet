import { Psbt, Transaction } from 'bitcoinjs-lib';
import ECPairFactory, { type ECPairAPI } from 'ecpair';
import * as ecc from '@bitcoinerlab/secp256k1';
import { Buffer } from 'buffer';
import { smartiecoin, COIN, DEFAULT_FEE_RATE, API_BASE } from './network';
import { fetchUtxos } from './api';

const ECPair: ECPairAPI = ECPairFactory(ecc);

export interface UTXO {
  txid: string;
  outputIndex: number;
  satoshis: number;
  script: string;
}

// Estimate P2PKH transaction size
function estimateSize(inputCount: number, outputCount: number): number {
  return inputCount * 148 + outputCount * 34 + 10;
}

// Fetch raw transaction hex
async function fetchRawTxHex(txid: string): Promise<string> {
  const res = await fetch(`${API_BASE}/rawtx/${txid}`);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Failed to fetch raw tx');
  return data.hex;
}

// Build and sign a transaction
export async function buildTransaction(params: {
  fromAddress: string;
  toAddress: string;
  amountDuffs: number;
  privateKey: Uint8Array;
  feeRate?: number;
}): Promise<{ hex: string; fee: number; txid: string }> {
  const { fromAddress, toAddress, amountDuffs, privateKey, feeRate = DEFAULT_FEE_RATE } = params;

  const utxos: UTXO[] = await fetchUtxos(fromAddress);
  if (utxos.length === 0) {
    throw new Error('No spendable outputs found');
  }

  // Sort largest first
  utxos.sort((a, b) => b.satoshis - a.satoshis);

  const selected: UTXO[] = [];
  let totalInput = 0;
  let estimatedFee = estimateSize(1, 2) * feeRate;

  for (const utxo of utxos) {
    selected.push(utxo);
    totalInput += utxo.satoshis;
    estimatedFee = estimateSize(selected.length, 2) * feeRate;
    if (totalInput >= amountDuffs + estimatedFee) break;
  }

  if (totalInput < amountDuffs + estimatedFee) {
    const available = totalInput / COIN;
    const needed = (amountDuffs + estimatedFee) / COIN;
    throw new Error(
      `Insufficient funds. Available: ${available.toFixed(8)} SMT, Needed: ${needed.toFixed(8)} SMT`
    );
  }

  // Fetch raw transactions for P2PKH signing
  const rawTxCache = new Map<string, Buffer>();
  for (const utxo of selected) {
    if (!rawTxCache.has(utxo.txid)) {
      const hex = await fetchRawTxHex(utxo.txid);
      rawTxCache.set(utxo.txid, Buffer.from(hex, 'hex'));
    }
  }

  const keyPair = ECPair.fromPrivateKey(Buffer.from(privateKey), {
    network: smartiecoin,
  });

  const psbt = new Psbt({ network: smartiecoin });

  for (const utxo of selected) {
    psbt.addInput({
      hash: utxo.txid,
      index: utxo.outputIndex,
      nonWitnessUtxo: rawTxCache.get(utxo.txid)!,
    });
  }

  // Payment output
  psbt.addOutput({ address: toAddress, value: amountDuffs });

  // Change output
  const change = totalInput - amountDuffs - estimatedFee;
  const DUST_THRESHOLD = 546;

  if (change > DUST_THRESHOLD) {
    psbt.addOutput({ address: fromAddress, value: change });
  } else {
    estimatedFee = totalInput - amountDuffs;
  }

  for (let i = 0; i < selected.length; i++) {
    psbt.signInput(i, keyPair);
  }

  psbt.finalizeAllInputs();
  const tx: Transaction = psbt.extractTransaction();

  return { hex: tx.toHex(), fee: estimatedFee, txid: tx.getId() };
}

// Format duffs to SMT string
export function duffsToSmt(duffs: number): string {
  return (duffs / COIN).toFixed(8);
}

// Parse SMT string to duffs
export function smtToDuffs(smt: string): number {
  const value = parseFloat(smt);
  if (isNaN(value) || value < 0) throw new Error('Invalid amount');
  return Math.round(value * COIN);
}
