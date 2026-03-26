import React from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet, RefreshControl, ScrollView,
} from 'react-native';
import { colors } from '../lib/theme';
import { COIN } from '../lib/network';
import type { BalanceResponse } from '../lib/api';

interface Props {
  address: string;
  balance: BalanceResponse | null;
  onSend: () => void;
  onReceive: () => void;
  onHistory: () => void;
  onLogout: () => void;
  onRefresh: () => void;
}

export default function DashboardScreen({
  address, balance, onSend, onReceive, onHistory, onLogout, onRefresh,
}: Props) {
  const [refreshing, setRefreshing] = React.useState(false);

  const handleRefresh = async () => {
    setRefreshing(true);
    onRefresh();
    setTimeout(() => setRefreshing(false), 1000);
  };

  const balanceSmt = balance ? (balance.balance / COIN).toFixed(8) : '---';

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      refreshControl={
        <RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor={colors.primary} />
      }
    >
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Smartiecoin Wallet</Text>
        <TouchableOpacity onPress={onLogout}>
          <Text style={styles.logoutText}>Lock</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.balanceCard}>
        <Text style={styles.balanceLabel}>Balance</Text>
        <Text style={styles.balanceAmount}>{balanceSmt}</Text>
        <Text style={styles.balanceCurrency}>SMT</Text>
        <Text style={styles.addressText} numberOfLines={1}>{address}</Text>
      </View>

      <View style={styles.actions}>
        <TouchableOpacity style={styles.actionBtn} onPress={onSend}>
          <View style={[styles.actionIcon, { backgroundColor: '#3b82f6' }]}>
            <Text style={styles.actionIconText}>^</Text>
          </View>
          <Text style={styles.actionLabel}>Send</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.actionBtn} onPress={onReceive}>
          <View style={[styles.actionIcon, { backgroundColor: '#22c55e' }]}>
            <Text style={styles.actionIconText}>v</Text>
          </View>
          <Text style={styles.actionLabel}>Receive</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.actionBtn} onPress={onHistory}>
          <View style={[styles.actionIcon, { backgroundColor: '#8b5cf6' }]}>
            <Text style={styles.actionIconText}>#</Text>
          </View>
          <Text style={styles.actionLabel}>History</Text>
        </TouchableOpacity>
      </View>

      {balance && (
        <View style={styles.statsCard}>
          <View style={styles.statRow}>
            <Text style={styles.statLabel}>Total Received</Text>
            <Text style={styles.statValueGreen}>
              {(balance.received / COIN).toFixed(8)} SMT
            </Text>
          </View>
          <View style={styles.statRow}>
            <Text style={styles.statLabel}>Total Sent</Text>
            <Text style={styles.statValueRed}>
              {(balance.sent / COIN).toFixed(8)} SMT
            </Text>
          </View>
        </View>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },
  content: { padding: 24, paddingTop: 60 },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 24,
  },
  headerTitle: { fontSize: 18, fontWeight: '600', color: colors.text },
  logoutText: { color: colors.primary, fontSize: 15 },
  balanceCard: {
    backgroundColor: colors.bgCard,
    borderRadius: 16,
    padding: 24,
    alignItems: 'center',
    marginBottom: 24,
    borderWidth: 1,
    borderColor: colors.border,
  },
  balanceLabel: { color: colors.textSecondary, fontSize: 14, marginBottom: 8 },
  balanceAmount: { color: colors.text, fontSize: 36, fontWeight: 'bold' },
  balanceCurrency: { color: colors.primary, fontSize: 16, fontWeight: '600', marginTop: 4 },
  addressText: {
    color: colors.textMuted,
    fontSize: 11,
    marginTop: 12,
    maxWidth: '90%',
  },
  actions: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginBottom: 24,
  },
  actionBtn: { alignItems: 'center', gap: 8 },
  actionIcon: {
    width: 56,
    height: 56,
    borderRadius: 28,
    justifyContent: 'center',
    alignItems: 'center',
  },
  actionIconText: { color: 'white', fontSize: 22, fontWeight: 'bold' },
  actionLabel: { color: colors.textSecondary, fontSize: 13 },
  statsCard: {
    backgroundColor: colors.bgCard,
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: colors.border,
    gap: 12,
  },
  statRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  statLabel: { color: colors.textSecondary, fontSize: 14 },
  statValueGreen: { color: colors.success, fontSize: 14, fontWeight: '500' },
  statValueRed: { color: colors.danger, fontSize: 14, fontWeight: '500' },
});
