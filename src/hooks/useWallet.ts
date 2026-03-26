import { useState, useEffect, useCallback } from 'react';
import {
  WalletData,
  createWallet,
  importWallet,
  unlockWallet,
  saveWallet,
  loadWallet,
  deleteWallet,
} from '../lib/wallet';
import { fetchBalance, BalanceResponse } from '../lib/api';

export type Screen =
  | 'loading'
  | 'landing'
  | 'create'
  | 'backup'
  | 'import'
  | 'unlock'
  | 'dashboard'
  | 'send'
  | 'receive'
  | 'history';

export interface WalletState {
  screen: Screen;
  walletData: WalletData | null;
  privateKey: Uint8Array | null;
  mnemonic: string | null;
  balance: BalanceResponse | null;
  error: string | null;
  loading: boolean;
}

export function useWallet() {
  const [state, setState] = useState<WalletState>({
    screen: 'loading',
    walletData: null,
    privateKey: null,
    mnemonic: null,
    balance: null,
    error: null,
    loading: false,
  });

  // Load wallet on mount
  useEffect(() => {
    loadWallet().then((data) => {
      setState((s) => ({
        ...s,
        screen: data ? 'unlock' : 'landing',
        walletData: data,
      }));
    });
  }, []);

  // Auto-refresh balance every 30s
  useEffect(() => {
    if (!state.walletData || !state.privateKey) return;

    const refresh = () => {
      fetchBalance(state.walletData!.address)
        .then((bal) => setState((s) => ({ ...s, balance: bal })))
        .catch(() => {});
    };

    refresh();
    const interval = setInterval(refresh, 30_000);
    return () => clearInterval(interval);
  }, [state.walletData, state.privateKey]);

  const navigate = useCallback((screen: Screen) => {
    setState((s) => ({ ...s, screen, error: null }));
  }, []);

  const setError = useCallback((error: string | null) => {
    setState((s) => ({ ...s, error }));
  }, []);

  const handleCreate = useCallback(async (password: string) => {
    setState((s) => ({ ...s, loading: true, error: null }));
    try {
      const { walletData, mnemonic } = createWallet(password);
      await saveWallet(walletData);
      const { privateKey } = unlockWallet(walletData, password);
      setState((s) => ({
        ...s,
        walletData,
        mnemonic,
        privateKey,
        loading: false,
        screen: 'backup',
      }));
    } catch (e: any) {
      setState((s) => ({ ...s, loading: false, error: e.message }));
    }
  }, []);

  const handleImport = useCallback(async (mnemonic: string, password: string) => {
    setState((s) => ({ ...s, loading: true, error: null }));
    try {
      const walletData = importWallet(mnemonic, password);
      await saveWallet(walletData);
      const { privateKey } = unlockWallet(walletData, password);
      setState((s) => ({
        ...s,
        walletData,
        privateKey,
        mnemonic: null,
        loading: false,
        screen: 'dashboard',
      }));
    } catch (e: any) {
      setState((s) => ({ ...s, loading: false, error: e.message }));
    }
  }, []);

  const handleUnlock = useCallback(async (password: string) => {
    if (!state.walletData) return;
    setState((s) => ({ ...s, loading: true, error: null }));
    try {
      const { privateKey } = unlockWallet(state.walletData, password);
      setState((s) => ({
        ...s,
        privateKey,
        loading: false,
        screen: 'dashboard',
      }));
    } catch (e: any) {
      setState((s) => ({ ...s, loading: false, error: e.message }));
    }
  }, [state.walletData]);

  const handleLogout = useCallback(async () => {
    await deleteWallet();
    setState({
      screen: 'landing',
      walletData: null,
      privateKey: null,
      mnemonic: null,
      balance: null,
      error: null,
      loading: false,
    });
  }, []);

  const refreshBalance = useCallback(async () => {
    if (!state.walletData) return;
    try {
      const bal = await fetchBalance(state.walletData.address);
      setState((s) => ({ ...s, balance: bal }));
    } catch {
      // silent fail
    }
  }, [state.walletData]);

  return {
    ...state,
    navigate,
    setError,
    handleCreate,
    handleImport,
    handleUnlock,
    handleLogout,
    refreshBalance,
  };
}
