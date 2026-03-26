import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView, Alert } from 'react-native';
import { colors } from '../lib/theme';

interface Props {
  mnemonic: string;
  onContinue: () => void;
}

export default function BackupMnemonicScreen({ mnemonic, onContinue }: Props) {
  const [confirmed, setConfirmed] = useState(false);
  const words = mnemonic.split(' ');

  const handleContinue = () => {
    if (!confirmed) {
      Alert.alert(
        'Have you saved your phrase?',
        'If you lose this phrase, you will lose access to your wallet forever.',
        [
          { text: 'Go Back', style: 'cancel' },
          { text: 'Yes, I saved it', onPress: () => { setConfirmed(true); onContinue(); } },
        ]
      );
    } else {
      onContinue();
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>Backup Recovery Phrase</Text>
      <Text style={styles.subtitle}>
        Write down these 12 words in order. This is the ONLY way to recover your wallet.
      </Text>

      <View style={styles.warningBox}>
        <Text style={styles.warningText}>
          NEVER share this phrase. Anyone with it can steal your funds.
        </Text>
      </View>

      <View style={styles.wordGrid}>
        {words.map((word, i) => (
          <View key={i} style={styles.wordItem}>
            <Text style={styles.wordNum}>{i + 1}</Text>
            <Text style={styles.wordText}>{word}</Text>
          </View>
        ))}
      </View>

      <TouchableOpacity style={styles.continueBtn} onPress={handleContinue}>
        <Text style={styles.continueBtnText}>I've Saved My Phrase</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  content: { padding: 24, paddingTop: 60 },
  title: { fontSize: 24, fontWeight: 'bold', color: colors.text, marginBottom: 8 },
  subtitle: { fontSize: 14, color: colors.textSecondary, marginBottom: 16, lineHeight: 20 },
  warningBox: {
    backgroundColor: '#7f1d1d',
    borderRadius: 10,
    padding: 14,
    marginBottom: 24,
  },
  warningText: { color: '#fca5a5', fontSize: 13, textAlign: 'center', fontWeight: '600' },
  wordGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginBottom: 32,
  },
  wordItem: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.bgCard,
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 14,
    width: '47%',
    borderWidth: 1,
    borderColor: colors.border,
  },
  wordNum: {
    color: colors.textMuted,
    fontSize: 12,
    width: 20,
    fontWeight: '600',
  },
  wordText: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '500',
  },
  continueBtn: {
    backgroundColor: colors.primary,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
  },
  continueBtnText: { color: colors.text, fontSize: 16, fontWeight: '600' },
});
