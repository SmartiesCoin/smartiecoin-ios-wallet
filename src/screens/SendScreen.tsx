import React, { useState } from 'react';
import {
  View, Text, TextInput, TouchableOpacity,
  StyleSheet, ActivityIndicator, KeyboardAvoidingView, Platform, ScrollView, Alert,
} from 'react-native';
import { colors } from '../lib/theme';
import { COIN } from '../lib/network';
import { buildTransaction, smtToDuffs, duffsToSmt } from '../lib/transaction';
import { broadcastTx } from '../lib/api';
import type { BalanceResponse } from '../lib/api';

interface Props {
  address: string;
  privateKey: Uint8Array;
  balance: BalanceResponse | null;
  onBack: () => void;
  onSuccess: () => void;
}

type Step = 'form' | 'confirm' | 'sending' | 'success';

export default function SendScreen({ address, privateKey, balance, onBack, onSuccess }: Props) {
  const [step, setStep] = useState<Step>('form');
  const [toAddress, setToAddress] = useState('');
  const [amount, setAmount] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [txResult, setTxResult] = useState<{ txid: string; fee: number } | null>(null);

  const availableSmt = balance ? balance.balance / COIN : 0;

  const handleReview = () => {
    setError(null);
    if (!toAddress.match(/^[SR][1-9A-HJ-NP-Za-km-z]{25,34}$/)) {
      setError('Invalid Smartiecoin address');
      return;
    }
    const val = parseFloat(amount);
    if (isNaN(val) || val <= 0) {
      setError('Invalid amount');
      return;
    }
    if (val > availableSmt) {
      setError('Insufficient funds');
      return;
    }
    setStep('confirm');
  };

  const handleSend = async () => {
    setStep('sending');
    setError(null);
    try {
      const amountDuffs = smtToDuffs(amount);
      const result = await buildTransaction({
        fromAddress: address,
        toAddress,
        amountDuffs,
        privateKey,
      });
      const { txid } = await broadcastTx(result.hex);
      setTxResult({ txid, fee: result.fee });
      setStep('success');
    } catch (e: any) {
      setError(e.message);
      setStep('confirm');
    }
  };

  if (step === 'success' && txResult) {
    return (
      <View style={styles.container}>
        <View style={styles.successCard}>
          <Text style={styles.successIcon}>OK</Text>
          <Text style={styles.successTitle}>Transaction Sent!</Text>
          <Text style={styles.successAmount}>{amount} SMT</Text>
          <Text style={styles.successLabel}>To</Text>
          <Text style={styles.successAddress} numberOfLines={2}>{toAddress}</Text>
          <Text style={styles.successLabel}>Fee</Text>
          <Text style={styles.successFee}>{duffsToSmt(txResult.fee)} SMT</Text>
          <Text style={styles.successLabel}>TXID</Text>
          <Text style={styles.successTxid} numberOfLines={2}>{txResult.txid}</Text>
        </View>
        <TouchableOpacity style={styles.primaryBtn} onPress={onSuccess}>
          <Text style={styles.primaryBtnText}>Back to Wallet</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (step === 'confirm' || step === 'sending') {
    return (
      <View style={styles.container}>
        <Text style={styles.title}>Confirm Transaction</Text>

        <View style={styles.confirmCard}>
          <View style={styles.confirmRow}>
            <Text style={styles.confirmLabel}>To</Text>
            <Text style={styles.confirmValue} numberOfLines={1}>{toAddress}</Text>
          </View>
          <View style={styles.confirmRow}>
            <Text style={styles.confirmLabel}>Amount</Text>
            <Text style={styles.confirmValue}>{amount} SMT</Text>
          </View>
        </View>

        {error && <Text style={styles.errorText}>{error}</Text>}

        <View style={styles.confirmButtons}>
          <TouchableOpacity
            style={styles.secondaryBtn}
            onPress={() => setStep('form')}
            disabled={step === 'sending'}
          >
            <Text style={styles.secondaryBtnText}>Back</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.primaryBtn, { flex: 1 }, step === 'sending' && styles.btnDisabled]}
            onPress={handleSend}
            disabled={step === 'sending'}
          >
            {step === 'sending' ? (
              <ActivityIndicator color={colors.text} />
            ) : (
              <Text style={styles.primaryBtnText}>Send</Text>
            )}
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView contentContainerStyle={{ paddingBottom: 40 }}>
        <TouchableOpacity onPress={onBack} style={styles.backBtn}>
          <Text style={styles.backText}>{'< Back'}</Text>
        </TouchableOpacity>

        <Text style={styles.title}>Send SMT</Text>
        <Text style={styles.available}>
          Available: {availableSmt.toFixed(8)} SMT
        </Text>

        <Text style={styles.label}>Recipient Address</Text>
        <TextInput
          style={styles.input}
          value={toAddress}
          onChangeText={setToAddress}
          placeholder="S... or R..."
          placeholderTextColor={colors.textMuted}
          autoCapitalize="none"
          autoCorrect={false}
        />

        <Text style={styles.label}>Amount (SMT)</Text>
        <TextInput
          style={styles.input}
          value={amount}
          onChangeText={setAmount}
          placeholder="0.00000000"
          placeholderTextColor={colors.textMuted}
          keyboardType="decimal-pad"
        />

        <TouchableOpacity
          style={styles.maxBtn}
          onPress={() => setAmount(availableSmt.toFixed(8))}
        >
          <Text style={styles.maxBtnText}>MAX</Text>
        </TouchableOpacity>

        {error && <Text style={styles.errorText}>{error}</Text>}

        <TouchableOpacity
          style={[styles.primaryBtn, (!toAddress || !amount) && styles.btnDisabled]}
          onPress={handleReview}
          disabled={!toAddress || !amount}
        >
          <Text style={styles.primaryBtnText}>Review</Text>
        </TouchableOpacity>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: 24, paddingTop: 60 },
  backBtn: { marginBottom: 24 },
  backText: { color: colors.primary, fontSize: 16 },
  title: { fontSize: 24, fontWeight: 'bold', color: colors.text, marginBottom: 8 },
  available: { color: colors.textSecondary, fontSize: 14, marginBottom: 24 },
  label: { color: colors.textSecondary, fontSize: 14, marginTop: 12, marginBottom: 6 },
  input: {
    backgroundColor: colors.bgInput,
    borderRadius: 10,
    padding: 14,
    fontSize: 16,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border,
  },
  maxBtn: { alignSelf: 'flex-end', marginTop: 8 },
  maxBtnText: { color: colors.primary, fontSize: 13, fontWeight: '600' },
  errorText: { color: colors.danger, fontSize: 12, marginTop: 8 },
  primaryBtn: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    marginTop: 24,
  },
  primaryBtnText: { color: colors.text, fontSize: 16, fontWeight: '600' },
  btnDisabled: { opacity: 0.5 },
  secondaryBtn: {
    backgroundColor: colors.bgCard,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.border,
  },
  secondaryBtnText: { color: colors.textSecondary, fontSize: 16, fontWeight: '600' },
  confirmCard: {
    backgroundColor: colors.bgCard,
    borderRadius: 12,
    padding: 16,
    gap: 16,
    marginVertical: 16,
    borderWidth: 1,
    borderColor: colors.border,
  },
  confirmRow: { gap: 4 },
  confirmLabel: { color: colors.textMuted, fontSize: 12 },
  confirmValue: { color: colors.text, fontSize: 15, fontWeight: '500' },
  confirmButtons: { flexDirection: 'row', gap: 12, marginTop: 8 },
  successCard: {
    backgroundColor: colors.bgCard,
    borderRadius: 16,
    padding: 24,
    alignItems: 'center',
    marginVertical: 24,
    gap: 8,
    borderWidth: 1,
    borderColor: colors.success,
  },
  successIcon: { color: colors.success, fontSize: 32, fontWeight: 'bold', marginBottom: 8 },
  successTitle: { color: colors.text, fontSize: 20, fontWeight: 'bold' },
  successAmount: { color: colors.success, fontSize: 28, fontWeight: 'bold', marginVertical: 8 },
  successLabel: { color: colors.textMuted, fontSize: 12, marginTop: 4 },
  successAddress: { color: colors.textSecondary, fontSize: 13, textAlign: 'center' },
  successFee: { color: colors.textSecondary, fontSize: 13 },
  successTxid: { color: colors.textMuted, fontSize: 11, textAlign: 'center' },
});
