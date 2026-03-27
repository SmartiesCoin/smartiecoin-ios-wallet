import SwiftUI

struct DashboardView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let address: String
    let balance: BalanceResponse?
    let onSend: () -> Void
    let onReceive: () -> Void
    let onHistory: () -> Void
    let onLogout: () -> Void
    let onRefresh: () -> Void
    let onNetwork: () -> Void
    var spvClient: SPVClient?

    @State private var isRefreshing = false

    private var balanceDisplay: String {
        guard let balance else { return "---" }
        return SmartiecoinNetwork.smtToDisplay(balance.balance)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        HStack(spacing: 10) {
                            Image("AppIconDisplay")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text("Smartiecoin Wallet")
                                .font(.headline)
                                .foregroundColor(AppColors.text)
                        }

                        Spacer()

                        Button(action: onLogout) {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                Text("Lock")
                            }
                            .foregroundColor(AppColors.primary)
                        }
                    }
                    .padding(.bottom, 24)

                    #if WALLET_MODE_SPV
                    // SPV Sync Banner
                    if let spv = spvClient, spv.syncState != .synchronized {
                        syncBanner(spv: spv)
                    }
                    #endif

                    if sizeClass == .regular {
                        // iPad: side-by-side layout
                        HStack(alignment: .top, spacing: 24) {
                            VStack(spacing: 24) {
                                balanceCard
                                actionButtons
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: 24) {
                                #if WALLET_MODE_SPV
                                networkCard
                                #endif
                                statsCard
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        // iPhone: stacked layout
                        VStack(spacing: 24) {
                            balanceCard
                            actionButtons
                            #if WALLET_MODE_SPV
                            networkCard
                            #endif
                            statsCard
                        }
                    }
                }
                .frame(maxWidth: sizeClass == .regular ? 900 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, sizeClass == .regular ? 40 : 24)
                .padding(.top, sizeClass == .regular ? 40 : 20)
                .padding(.bottom, 40)
            }
            .refreshable {
                onRefresh()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        .background(AppColors.bg)
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        VStack(spacing: 8) {
            Text("Balance")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)

            Text(balanceDisplay)
                .font(.system(size: sizeClass == .regular ? 44 : 36, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.text)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("SMT")
                .font(.headline.weight(.semibold))
                .foregroundColor(AppColors.primary)

            Text(address)
                .font(.caption2)
                .foregroundColor(AppColors.textMuted)
                .lineLimit(1)
                .padding(.top, 8)
                .frame(maxWidth: 280)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: sizeClass == .regular ? 24 : 16) {
            ActionButton(
                title: "Send",
                icon: "arrow.up.circle.fill",
                color: Color(hex: 0x3B82F6),
                action: onSend
            )

            ActionButton(
                title: "Receive",
                icon: "arrow.down.circle.fill",
                color: AppColors.success,
                action: onReceive
            )

            ActionButton(
                title: "History",
                icon: "clock.fill",
                color: Color(hex: 0x8B5CF6),
                action: onHistory
            )
        }
    }

    // MARK: - Stats Card

    // MARK: - Sync Banner

    private func syncBanner(spv: SPVClient) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(AppColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(spv.syncState.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.warning)
                Text("Block \(spv.blockHeight) / \(spv.networkHeight) (\(Int(spv.syncProgress * 100))%)")
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted)
            }
            Spacer()
            Text("\(spv.peerCount) peers")
                .font(.caption)
                .foregroundColor(AppColors.textMuted)
        }
        .padding(14)
        .background(AppColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.warning.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Network Card

    private var networkCard: some View {
        Button(action: onNetwork) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(spvClient?.syncState == .synchronized ? AppColors.success : AppColors.warning)
                            .frame(width: 8, height: 8)
                        Text("P2P Network")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.text)
                    }
                    Text("\(spvClient?.peerCount ?? 0) peers connected")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                }
                Spacer()
                Image(systemName: "network")
                    .foregroundColor(AppColors.primary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(16)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var statsCard: some View {
        if let balance {
            VStack(spacing: 16) {
                Text("Summary")
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("Total Received")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("\(SmartiecoinNetwork.smtToDisplay(balance.received)) SMT")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.success)
                }

                Divider()
                    .background(AppColors.border)

                HStack {
                    Text("Total Sent")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("\(SmartiecoinNetwork.smtToDisplay(balance.sent)) SMT")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.danger)
                }
            }
            .padding(20)
            .cardStyle()
        }
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: sizeClass == .regular ? 32 : 26))
                    .foregroundColor(.white)
                    .frame(width: sizeClass == .regular ? 64 : 56,
                           height: sizeClass == .regular ? 64 : 56)
                    .background(color)
                    .clipShape(Circle())
                    .shadow(color: color.opacity(0.3), radius: 8, y: 4)

                Text(title)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
