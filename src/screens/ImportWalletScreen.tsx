import React, { useState } from 'react';
import {
  View, Text, TextInput, TouchableOpacity,
  StyleSheet, ActivityIndicator, KeyboardAvoidingView, Platform, ScrollView,
} from 'react-native';
import { colors } from '../lib/theme';

interface Props {
  onSubmit: (mnemonic: string, password: string) => void;
  onBack: () => void;
  loading: boolean;
  error: string | null;
}

export default function ImportWalletScreen({ onSubmit, onBack, loading, error }: Props) {
  const [mnemonic, setMnemonic] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');

  const wordCount = mnemonic.trim().split(/\s+/).filter(Boolean).length;
  const canSubmit = wordCount === 12 && password.length >= 8 && password === confirm && !loading;

  const handleSubmit = () => {
    if (canSubmit) onSubmit(mnemonic.trim(), password);
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView contentContainerStyle={styles.content}>
        <TouchableOpacity onPress={onBack} style={styles.backBtn}>
          <Text style={styles.backText}>{'< Back'}</Text>
        </TouchableOpacity>

        <Text style={styles.title}>Import Wallet</Text>
        <Text style={styles.subtitle}>Enter your 12-word recovery phrase</Text>

        <Text style={styles.label}>Recovery Phrase</Text>
        <TextInput
          style={[styles.input, styles.mnemonicInput]}
          value={mnemonic}
          onChangeText={setMnemonic}
          placeholder="Enter 12 words separated by spaces"
          placeholderTextColor={colors.textMuted}
          autoCapitalize="none"
          autoCorrect={false}
          multiline
          numberOfLines={3}
        />
        <Text style={styles.wordCount}>{wordCount}/12 words</Text>

        <Text style={styles.label}>New Password</Text>
        <TextInput
          style={styles.input}
          secureTextEntry
          value={password}
          onChangeText={setPassword}
          placeholder="At least 8 characters"
          placeholderTextColor={colors.textMuted}
          autoCapitalize="none"
        />

        <Text style={styles.label}>Confirm Password</Text>
        <TextInput
          style={styles.input}
          secureTextEntry
          value={confirm}
          onChangeText={setConfirm}
          placeholder="Repeat your password"
          placeholderTextColor={colors.textMuted}
          autoCapitalize="none"
        />

        {error && <Text style={styles.errorText}>{error}</Text>}

        <TouchableOpacity
          style={[styles.submitBtn, !canSubmit && styles.submitBtnDisabled]}
          onPress={handleSubmit}
          disabled={!canSubmit}
        >
          {loading ? (
            <ActivityIndicator color={colors.text} />
          ) : (
            <Text style={styles.submitText}>Import Wallet</Text>
          )}
        </TouchableOpacity>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  content: { padding: 24, paddingTop: 60 },
  backBtn: { marginBottom: 24 },
  backText: { color: colors.primary, fontSize: 16 },
  title: { fontSize: 24, fontWeight: 'bold', color: colors.text, marginBottom: 8 },
  subtitle: { fontSize: 14, color: colors.textSecondary, marginBottom: 24 },
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
  mnemonicInput: { minHeight: 80, textAlignVertical: 'top' },
  wordCount: { color: colors.textMuted, fontSize: 12, marginTop: 4, textAlign: 'right' },
  errorText: { color: colors.danger, fontSize: 12, marginTop: 8 },
  submitBtn: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    marginTop: 24,
  },
  submitBtnDisabled: { opacity: 0.5 },
  submitText: { color: colors.text, fontSize: 16, fontWeight: '600' },
});
