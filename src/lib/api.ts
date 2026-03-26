import { API_BASE, COIN } from './network';
import type { UTXO } from './transaction';

interface ExplorerUTXO {
  txid: string;
  vout: number;
  amount: number;
  scriptPubKey: string;
}

async function apiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
    },
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error || `API error ${res.status}`);
  }
  return data as T;
}

export interface BalanceResponse {
  balance: number;
  received: number;
  sent: number;
}

export async function fetchBalance(address: string): Promise<BalanceResponse> {
  return apiFetch<BalanceResponse>(`/balance/${address}`);
}

export async function fetchUtxos(address: string): Promise<UTXO[]> {
  const raw = await apiFetch<ExplorerUTXO[]>(`/utxos/${address}`);
  return raw.map((u) => ({
    txid: u.txid,
    outputIndex: u.vout,
    satoshis: Math.round(u.amount * COIN),
    script: u.scriptPubKey,
  }));
}

export interface HistoryTx {
  txid: string;
  sent: number;
  received: number;
  balance: number;
  timestamp: number;
}

export async function fetchHistory(address: string): Promise<HistoryTx[]> {
  return apiFetch<HistoryTx[]>(`/history/${address}`);
}

export async function broadcastTx(hex: string): Promise<{ txid: string }> {
  return apiFetch<{ txid: string }>('/broadcast', {
    method: 'POST',
    body: JSON.stringify({ hex }),
  });
}
