import UIKit
import SwiftUI

@main
struct SmartiecoinWalletApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = WalletViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationService.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationService.shared.handleRegisteredDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationService.shared.handleRegistrationError(error)
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: WalletViewModel

    var body: some View {
        Group {
            switch viewModel.screen {
            case .loading:
                loadingView

            case .landing:
                LandingView(
                    onCreateWallet: { viewModel.navigate(to: .create) },
                    onImportWallet: { viewModel.navigate(to: .importWallet) }
                )

            case .create:
                CreateWalletView(
                    onSubmit: { viewModel.createWallet(password: $0) },
                    onBack: { viewModel.navigate(to: .landing) },
                    loading: viewModel.loading,
                    error: viewModel.error
                )

            case .backup:
                BackupMnemonicView(
                    mnemonic: viewModel.mnemonic ?? "",
                    onContinue: {
                        viewModel.navigate(to: .dashboard)
                        viewModel.startBalanceRefresh()
                    }
                )

            case .importWallet:
                ImportWalletView(
                    onSubmit: { viewModel.importWallet(mnemonic: $0, password: $1) },
                    onBack: { viewModel.navigate(to: .landing) },
                    loading: viewModel.loading,
                    error: viewModel.error
                )

            case .unlock:
                UnlockWalletView(
                    address: viewModel.walletData?.address ?? "",
                    onSubmit: { viewModel.unlock(password: $0) },
                    onBiometricUnlock: { viewModel.unlockWithBiometrics() },
                    onDelete: { viewModel.logout() },
                    biometricSupported: viewModel.biometricSupported,
                    biometricAvailable: viewModel.biometricUnlockAvailable,
                    biometryName: viewModel.biometryName,
                    loading: viewModel.loading,
                    error: viewModel.error
                )

            case .dashboard:
                DashboardView(
                    address: viewModel.walletData?.address ?? "",
                    balance: viewModel.balance,
                    onSend: { viewModel.navigate(to: .send) },
                    onReceive: { viewModel.navigate(to: .receive) },
                    onHistory: { viewModel.navigate(to: .history) },
                    onLogout: { viewModel.lock() },
                    onRefresh: { viewModel.refreshBalance() },
                    onNetwork: { viewModel.navigate(to: .networkStatus) },
                    onRevealKey: {
                        viewModel.clearRevealedMnemonic()
                        viewModel.navigate(to: .revealMnemonic)
                    },
                    onChangePassword: {
                        viewModel.clearPasswordChangeState()
                        viewModel.navigate(to: .changePassword)
                    },
                    biometricAvailable: viewModel.biometricUnlockAvailable,
                    biometryName: viewModel.biometryName,
                    spvClient: viewModel.spvClient
                )

            case .changePassword:
                ChangePasswordView(
                    loading: viewModel.loading,
                    error: viewModel.error,
                    success: viewModel.passwordChanged,
                    onSubmit: { current, new in
                        viewModel.changePassword(currentPassword: current, newPassword: new)
                    },
                    onBack: {
                        viewModel.clearPasswordChangeState()
                        viewModel.navigate(to: .dashboard)
                    }
                )

            case .revealMnemonic:
                RevealMnemonicView(
                    mnemonic: viewModel.revealedMnemonic,
                    loading: viewModel.loading,
                    error: viewModel.error,
                    onSubmit: { viewModel.revealMnemonic(password: $0) },
                    onBack: {
                        viewModel.clearRevealedMnemonic()
                        viewModel.navigate(to: .dashboard)
                    }
                )

            case .send:
                SendView(
                    address: viewModel.walletData?.address ?? "",
                    balance: viewModel.balance,
                    onBack: { viewModel.navigate(to: .dashboard) },
                    onSendTransaction: { toAddr, amount in
                        try await viewModel.sendTransaction(toAddress: toAddr, amount: amount)
                    },
                    onSuccess: {
                        viewModel.refreshBalance()
                        viewModel.navigate(to: .dashboard)
                    }
                )

            case .receive:
                ReceiveView(
                    address: viewModel.walletData?.address ?? "",
                    onBack: { viewModel.navigate(to: .dashboard) }
                )

            case .history:
                HistoryView(
                    address: viewModel.walletData?.address ?? "",
                    onBack: { viewModel.navigate(to: .dashboard) }
                )

            case .networkStatus:
                NetworkStatusView(
                    spvClient: viewModel.spvClient,
                    onBack: { viewModel.navigate(to: .dashboard) },
                    onAddPeer: { viewModel.addPeersFromText($0) },
                    onStartSPV: { viewModel.startSPVIfNeeded() }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.screen)
    }

    private var loadingView: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            ProgressView()
                .tint(AppColors.primary)
                .scaleEffect(1.5)
        }
    }
}
