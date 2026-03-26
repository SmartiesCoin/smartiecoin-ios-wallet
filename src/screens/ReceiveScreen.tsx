import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Alert } from 'react-native';
import * as Clipboard from 'expo-clipboard';
import QRCode from 'react-native-qrcode-svg';
import { colors } from '../lib/theme';

interface Props {
  address: string;
  onBack: () => void;
}

export default function ReceiveScreen({ address, onBack }: Props) {
  const handleCopy = async () => {
    await Clipboard.setStringAsync(address);
    Alert.alert('Copied', 'Address copied to clipboard');
  };

  return (
    <View style={styles.container}>
      <TouchableOpacity onPress={onBack} style={styles.backBtn}>
        <Text style={styles.backText}>{'< Back'}</Text>
      </TouchableOpacity>

      <Text style={styles.title}>Receive SMT</Text>
      <Text style={styles.subtitle}>
        Share your address or QR code to receive Smartiecoin
      </Text>

      <View style={styles.qrCard}>
        <View style={styles.qrWrapper}>
          <QRCode value={address} size={200} backgroundColor="white" color="black" />
        </View>

        <Text style={styles.address}>{address}</Text>

        <TouchableOpacity style={styles.copyBtn} onPress={handleCopy}>
          <Text style={styles.copyBtnText}>Copy Address</Text>
        </TouchableOpacity>
      </View>
    </View>
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
  qrCard: {
    backgroundColor: colors.bgCard,
    borderRadius: 16,
    padding: 24,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    gap: 16,
  },
  qrWrapper: {
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 12,
  },
  address: {
    color: colors.text,
    fontSize: 13,
    textAlign: 'center',
    fontWeight: '500',
  },
  copyBtn: {
    backgroundColor: colors.primary,
    borderRadius: 10,
    paddingVertical: 12,
    paddingHorizontal: 24,
  },
  copyBtnText: { color: colors.text, fontSize: 15, fontWeight: '600' },
});
