import React, { useState } from 'react';
import {
  View, Text, TextInput, TouchableOpacity,
  StyleSheet, ActivityIndicator, KeyboardAvoidingView, Platform, Alert,
} from 'react-native';
import { colors } from '../lib/theme';

interface Props {
  address: string;
  onSubmit: (password: string) => void;
  onDelete: () => void;
  loading: boolean;
  error: string | null;
}

export default function UnlockWalletScreen({ address, onSubmit, onDelete, loading, error }: Props) {
  const [password, setPassword] = useState('');

  const handleDelete = () => {
    Alert.alert(
      'Delete Wallet',
      'This will remove the wallet from this device. Make sure you have your recovery phrase backed up!',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: onDelete },
      ]
    );
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <View style={styles.header}>
        <Text style={styles.logo}>S</Text>
        <Text style={styles.title}>Unlock Wallet</Text>
        <Text style={styles.address} numberOfLines={1}>{address}</Text>
      </View>

      <View style={styles.form}>
        <TextInput
          style={styles.input}
          secureTextEntry
          value={password}
          onChangeText={setPassword}
          placeholder="Enter your password"
          placeholderTextColor={colors.textMuted}
          autoCapitalize="none"
          returnKeyType="go"
          onSubmitEditing={() => password && onSubmit(password)}
        />

        {error && <Text style={styles.errorText}>{error}</Text>}

        <TouchableOpacity
          style={[styles.submitBtn, (!password || loading) && styles.submitBtnDisabled]}
          onPress={() => onSubmit(password)}
          disabled={!password || loading}
        >
          {loading ? (
            <ActivityIndicator color={colors.text} />
          ) : (
            <Text style={styles.submitText}>Unlock</Text>
          )}
        </TouchableOpacity>

        <TouchableOpacity style={styles.deleteBtn} onPress={handleDelete}>
          <Text style={styles.deleteText}>Delete Wallet</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
    justifyContent: 'center',
    padding: 24,
  },
  header: { alignItems: 'center', marginBottom: 40 },
  logo: {
    fontSize: 48,
    fontWeight: 'bold',
    color: colors.primary,
    backgroundColor: colors.bgCard,
    width: 80,
    height: 80,
    textAlign: 'center',
    lineHeight: 80,
    borderRadius: 40,
    overflow: 'hidden',
    marginBottom: 16,
  },
  title: { fontSize: 22, fontWeight: 'bold', color: colors.text, marginBottom: 8 },
  address: { fontSize: 12, color: colors.textMuted, maxWidth: '80%' },
  form: { gap: 12 },
  input: {
    backgroundColor: colors.bgInput,
    borderRadius: 10,
    padding: 14,
    fontSize: 16,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border,
  },
  errorText: { color: colors.danger, fontSize: 12 },
  submitBtn: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
  },
  submitBtnDisabled: { opacity: 0.5 },
  submitText: { color: colors.text, fontSize: 16, fontWeight: '600' },
  deleteBtn: { alignItems: 'center', padding: 12, marginTop: 8 },
  deleteText: { color: colors.danger, fontSize: 14 },
});
