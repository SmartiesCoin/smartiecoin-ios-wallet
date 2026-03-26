import React, { useEffect, useState } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet, FlatList, ActivityIndicator,
} from 'react-native';
import { colors } from '../lib/theme';
import { COIN } from '../lib/network';
import { fetchHistory, HistoryTx } from '../lib/api';

interface Props {
  address: string;
  onBack: () => void;
}

export default function HistoryScreen({ address, onBack }: Props) {
  const [txs, setTxs] = useState<HistoryTx[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchHistory(address)
      .then(setTxs)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, [address]);

  const renderTx = ({ item }: { item: HistoryTx }) => {
    const isReceive = item.received > item.sent;
    const net = isReceive
      ? (item.received - item.sent) / COIN
      : (item.sent - item.received) / COIN;
    const date = new Date(item.timestamp * 1000);

    return (
      <View style={styles.txItem}>
        <View style={styles.txLeft}>
          <View style={[styles.txDot, { backgroundColor: isReceive ? colors.success : colors.danger }]} />
          <View>
            <Text style={styles.txType}>{isReceive ? 'Received' : 'Sent'}</Text>
            <Text style={styles.txDate}>
              {date.toLocaleDateString()} {date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </Text>
            <Text style={styles.txId} numberOfLines={1}>
              {item.txid.slice(0, 16)}...
            </Text>
          </View>
        </View>
        <Text style={[styles.txAmount, { color: isReceive ? colors.success : colors.danger }]}>
          {isReceive ? '+' : '-'}{net.toFixed(8)}
        </Text>
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <TouchableOpacity onPress={onBack} style={styles.backBtn}>
        <Text style={styles.backText}>{'< Back'}</Text>
      </TouchableOpacity>

      <Text style={styles.title}>Transaction History</Text>

      {loading && <ActivityIndicator color={colors.primary} style={{ marginTop: 40 }} />}
      {error && <Text style={styles.errorText}>{error}</Text>}

      {!loading && txs.length === 0 && !error && (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>No transactions yet</Text>
        </View>
      )}

      <FlatList
        data={txs}
        renderItem={renderTx}
        keyExtractor={(item) => item.txid}
        contentContainerStyle={{ gap: 8, paddingBottom: 40 }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg, padding: 24, paddingTop: 60 },
  backBtn: { marginBottom: 24 },
  backText: { color: colors.primary, fontSize: 16 },
  title: { fontSize: 24, fontWeight: 'bold', color: colors.text, marginBottom: 16 },
  errorText: { color: colors.danger, fontSize: 14, marginTop: 16 },
  empty: { alignItems: 'center', marginTop: 60 },
  emptyText: { color: colors.textMuted, fontSize: 16 },
  txItem: {
    backgroundColor: colors.bgCard,
    borderRadius: 10,
    padding: 14,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.border,
  },
  txLeft: { flexDirection: 'row', alignItems: 'center', gap: 10, flex: 1 },
  txDot: { width: 10, height: 10, borderRadius: 5 },
  txType: { color: colors.text, fontSize: 14, fontWeight: '600' },
  txDate: { color: colors.textMuted, fontSize: 11, marginTop: 2 },
  txId: { color: colors.textMuted, fontSize: 10, marginTop: 2, maxWidth: 130 },
  txAmount: { fontSize: 14, fontWeight: '600' },
});
