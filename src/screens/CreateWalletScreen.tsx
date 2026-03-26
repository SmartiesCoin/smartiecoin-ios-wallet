import React, { useState } from 'react';
import {
  View, Text, TextInput, TouchableOpacity,
  StyleSheet, ActivityIndicator, KeyboardAvoidingView, Platform,
} from 'react-native';
import { colors } from '../lib/theme';

interface Props {
  onSubmit: (password: string) => void;
  onBack: () => void;
  loading: boolean;
  error: string | null;
}

export default function CreateWalletScreen({ onSubmit, onBack, loading, error }: Props) {
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');

  const canSubmit = password.length >= 8 && password === confirm && !loading;

  const handleSubmit = () => {
    if (canSubmit) onSubmit(password);
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <TouchableOpacity onPress={onBack} style={styles.backBtn}>
        <Text style={styles.backText}>{'< Back'}</Text>
      </TouchableOpacity>

      <Text style={styles.title}>Create Wallet</Text>
      <Text style={styles.subtitle}>Set a password to encrypt your wallet</Text>

      <View style={styles.form}>
        <Text style={styles.label}>Password</Text>
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

        {password.length > 0 && password.length < 8 && (
          <Text style={styles.hint}>Password must be at least 8 characters</Text>
        )}
        {confirm.length > 0 && password !== confirm && (
          <Text style={styles.errorText}>Passwords don't match</Text>
        )}
        {error && <Text style={styles.errorText}>{error}</Text>}

        <TouchableOpacity
          style={[styles.submitBtn, !canSubmit && styles.submitBtnDisabled]}
          onPress={handleSubmit}
          disabled={!canSubmit}
        >
          {loading ? (
            <ActivityIndicator color={colors.text} />
          ) : (
            <Text style={styles.submitText}>Create Wallet</Text>
          )}
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
    padding: 24,
    paddingTop: 60,
  },
  backBtn: { marginBottom: 24 },
  backText: { color: colors.primary, fontSize: 16 },
  title: { fontSize: 24, fontWeight: 'bold', color: colors.text, marginBottom: 8 },
  subtitle: { fontSize: 14, color: colors.textSecondary, marginBottom: 32 },
  form: { gap: 12 },
  label: { color: colors.textSecondary, fontSize: 14, marginTop: 4 },
  input: {
    backgroundColor: colors.bgInput,
    borderRadius: 10,
    padding: 14,
    fontSize: 16,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border,
  },
  hint: { color: colors.warning, fontSize: 12 },
  errorText: { color: colors.danger, fontSize: 12 },
  submitBtn: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    marginTop: 16,
  },
  submitBtnDisabled: { opacity: 0.5 },
  submitText: { color: colors.text, fontSize: 16, fontWeight: '600' },
});
