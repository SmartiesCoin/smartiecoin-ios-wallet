// Polyfills must be first
import './src/lib/polyfills';

import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useWallet } from './src/hooks/useWallet';
import { colors } from './src/lib/theme';

import LandingScreen from './src/screens/LandingScreen';
import CreateWalletScreen from './src/screens/CreateWalletScreen';
import BackupMnemonicScreen from './src/screens/BackupMnemonicScreen';
import ImportWalletScreen from './src/screens/ImportWalletScreen';
import UnlockWalletScreen from './src/screens/UnlockWalletScreen';
import DashboardScreen from './src/screens/DashboardScreen';
import SendScreen from './src/screens/SendScreen';
import ReceiveScreen from './src/screens/ReceiveScreen';
import HistoryScreen from './src/screens/HistoryScreen';

export default function App() {
  const wallet = useWallet();

  const renderScreen = () => {
    switch (wallet.screen) {
      case 'loading':
        return (
          <View style={styles.loading}>
            <ActivityIndicator size="large" color={colors.primary} />
          </View>
        );

      case 'landing':
        return (
          <LandingScreen
            onCreateWallet={() => wallet.navigate('create')}
            onImportWallet={() => wallet.navigate('import')}
          />
        );

      case 'create':
        return (
          <CreateWalletScreen
            onSubmit={wallet.handleCreate}
            onBack={() => wallet.navigate('landing')}
            loading={wallet.loading}
            error={wallet.error}
          />
        );

      case 'backup':
        return (
          <BackupMnemonicScreen
            mnemonic={wallet.mnemonic || ''}
            onContinue={() => wallet.navigate('dashboard')}
          />
        );

      case 'import':
        return (
          <ImportWalletScreen
            onSubmit={wallet.handleImport}
            onBack={() => wallet.navigate('landing')}
            loading={wallet.loading}
            error={wallet.error}
          />
        );

      case 'unlock':
        return (
          <UnlockWalletScreen
            address={wallet.walletData?.address || ''}
            onSubmit={wallet.handleUnlock}
            onDelete={wallet.handleLogout}
            loading={wallet.loading}
            error={wallet.error}
          />
        );

      case 'dashboard':
        return (
          <DashboardScreen
            address={wallet.walletData?.address || ''}
            balance={wallet.balance}
            onSend={() => wallet.navigate('send')}
            onReceive={() => wallet.navigate('receive')}
            onHistory={() => wallet.navigate('history')}
            onLogout={wallet.handleLogout}
            onRefresh={wallet.refreshBalance}
          />
        );

      case 'send':
        return (
          <SendScreen
            address={wallet.walletData?.address || ''}
            privateKey={wallet.privateKey!}
            balance={wallet.balance}
            onBack={() => wallet.navigate('dashboard')}
            onSuccess={() => {
              wallet.refreshBalance();
              wallet.navigate('dashboard');
            }}
          />
        );

      case 'receive':
        return (
          <ReceiveScreen
            address={wallet.walletData?.address || ''}
            onBack={() => wallet.navigate('dashboard')}
          />
        );

      case 'history':
        return (
          <HistoryScreen
            address={wallet.walletData?.address || ''}
            onBack={() => wallet.navigate('dashboard')}
          />
        );
    }
  };

  return (
    <View style={styles.container}>
      <StatusBar style="light" />
      {renderScreen()}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  loading: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bg,
  },
});
